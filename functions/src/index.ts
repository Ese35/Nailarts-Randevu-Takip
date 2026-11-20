import {FieldValue, getFirestore, WriteBatch} from "firebase-admin/firestore";
import {initializeApp} from "firebase-admin/app";
import {logger} from "firebase-functions";
import {defineSecret, defineString} from "firebase-functions/params";
import {
  CallableRequest,
  HttpsError,
  onCall,
} from "firebase-functions/v2/https";

initializeApp();

const db = getFirestore();
const region = "europe-west1";
const whatsappAccessToken = defineSecret("WHATSAPP_ACCESS_TOKEN");
const adminEmail = defineString("ADMIN_EMAIL", {default: ""});
const phoneNumberId = defineString("WHATSAPP_PHONE_NUMBER_ID", {default: ""});
const templateName = defineString("WHATSAPP_TEMPLATE_NAME", {default: ""});
const templateLanguage = defineString("WHATSAPP_TEMPLATE_LANGUAGE", {
  default: "tr",
});
const graphApiVersion = defineString("WHATSAPP_GRAPH_API_VERSION", {
  default: "v22.0",
});

type CustomerRecord = {
  id: string;
  name: string;
  phone: string;
};

type AppointmentRecord = {
  id: string;
  date: string;
  time: string;
  customerId: string;
  service: string;
};

function requireUserId(request: CallableRequest<unknown>): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
  }
  if (request.auth.token.email_verified !== true) {
    throw new HttpsError(
      "permission-denied",
      "E-posta adresinizi doğrulamanız gerekiyor.",
    );
  }
  const configuredEmail = adminEmail.value().trim().toLowerCase();
  if (!configuredEmail) {
    throw new HttpsError(
      "failed-precondition",
      "Sunucu yöneticisi henüz yapılandırılmamış.",
    );
  }
  const email = typeof request.auth.token.email === "string" ?
    request.auth.token.email.toLowerCase() : "";
  if (email !== configuredEmail) {
    throw new HttpsError(
      "permission-denied",
      "Bu Firebase hesabı uygulamayı kullanmaya yetkili değil.",
    );
  }
  return request.auth.uid;
}

function requireAdministrator(request: CallableRequest<unknown>): string {
  return requireUserId(request);
}

function asRecord(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${label} geçersiz.`);
  }
  return value as Record<string, unknown>;
}

function requiredText(
  value: unknown,
  label: string,
  maxLength: number,
): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${label} gerekli.`);
  }
  const text = value.trim();
  if (text.length > maxLength) {
    throw new HttpsError("invalid-argument", `${label} çok uzun.`);
  }
  return text;
}

function recordId(value: unknown): string {
  const id = requiredText(value, "Kayıt kimliği", 128);
  if (!/^[A-Za-z0-9_-]+$/.test(id)) {
    throw new HttpsError("invalid-argument", "Kayıt kimliği geçersiz.");
  }
  return id;
}

function parseCustomers(value: unknown): CustomerRecord[] {
  if (!Array.isArray(value) || value.length > 2000) {
    throw new HttpsError("invalid-argument", "Müşteri listesi geçersiz.");
  }
  return value.map((entry) => {
    const item = asRecord(entry, "Müşteri");
    return {
      id: recordId(item.id),
      name: requiredText(item.name, "Müşteri adı", 200),
      phone: requiredText(item.phone, "Telefon numarası", 64),
    };
  });
}

function parseAppointments(value: unknown): AppointmentRecord[] {
  if (!Array.isArray(value) || value.length > 5000) {
    throw new HttpsError("invalid-argument", "Randevu listesi geçersiz.");
  }
  return value.map((entry) => {
    const item = asRecord(entry, "Randevu");
    const date = requiredText(item.date, "Randevu tarihi", 40);
    if (!Number.isFinite(Date.parse(date))) {
      throw new HttpsError("invalid-argument", "Randevu tarihi geçersiz.");
    }
    const time = requiredText(item.time, "Randevu saati", 5);
    if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(time)) {
      throw new HttpsError("invalid-argument", "Randevu saati geçersiz.");
    }
    return {
      id: recordId(item.id),
      date,
      time,
      customerId: recordId(item.customerId),
      service: requiredText(item.service, "İşlem bilgisi", 1000),
    };
  });
}

function parseIds(value: unknown, label: string): string[] {
  if (!Array.isArray(value) || value.length > 5000) {
    throw new HttpsError("invalid-argument", `${label} listesi geçersiz.`);
  }
  return value.map(recordId);
}

async function commitOperations(
  operations: Array<(batch: WriteBatch) => void>,
): Promise<void> {
  for (let offset = 0; offset < operations.length; offset += 450) {
    const batch = db.batch();
    for (const operation of operations.slice(offset, offset + 450)) {
      operation(batch);
    }
    await batch.commit();
  }
}

async function saveCustomersWithoutResurrection(
  uid: string,
  customers: CustomerRecord[],
): Promise<Set<string>> {
  const skipped = new Set<string>();
  const userRef = db.collection("users").doc(uid);
  for (let offset = 0; offset < customers.length; offset += 200) {
    const chunk = customers.slice(offset, offset + 200);
    await db.runTransaction(async (transaction) => {
      const tombstones = await Promise.all(chunk.map((customer) =>
        transaction.get(
          userRef.collection("deletedCustomers").doc(customer.id),
        )
      ));
      chunk.forEach((customer, index) => {
        if (tombstones[index].exists) {
          skipped.add(customer.id);
          return;
        }
        transaction.set(
          userRef.collection("customers").doc(customer.id),
          {...customer, updatedAt: FieldValue.serverTimestamp()},
          {merge: true},
        );
      });
    });
  }
  return skipped;
}

async function saveAppointmentsWithoutResurrection(
  uid: string,
  appointments: AppointmentRecord[],
): Promise<{deletedAppointmentIds: Set<string>; deletedCustomerIds: Set<string>}> {
  const deletedAppointmentIds = new Set<string>();
  const deletedCustomerIds = new Set<string>();
  const userRef = db.collection("users").doc(uid);
  for (let offset = 0; offset < appointments.length; offset += 200) {
    const chunk = appointments.slice(offset, offset + 200);
    await db.runTransaction(async (transaction) => {
      const tombstones = await Promise.all(chunk.map(async (appointment) => {
        const [appointmentTombstone, customerTombstone] = await Promise.all([
          transaction.get(
            userRef.collection("deletedAppointments").doc(appointment.id),
          ),
          transaction.get(
            userRef.collection("deletedCustomers").doc(appointment.customerId),
          ),
        ]);
        return {appointmentTombstone, customerTombstone};
      }));
      chunk.forEach((appointment, index) => {
        const {appointmentTombstone, customerTombstone} = tombstones[index];
        if (appointmentTombstone.exists || customerTombstone.exists) {
          deletedAppointmentIds.add(appointment.id);
          if (customerTombstone.exists) {
            deletedCustomerIds.add(appointment.customerId);
          }
          return;
        }
        transaction.set(
          userRef.collection("appointments").doc(appointment.id),
          {...appointment, updatedAt: FieldValue.serverTimestamp()},
          {merge: true},
        );
      });
    });
  }
  return {deletedAppointmentIds, deletedCustomerIds};
}

export const loadAccountData = onCall({region}, async (request) => {
  const uid = requireUserId(request);
  const userRef = db.collection("users").doc(uid);
  const [
    customers,
    appointments,
    deletedCustomers,
    deletedAppointments,
  ] = await Promise.all([
    userRef.collection("customers").get(),
    userRef.collection("appointments").get(),
    userRef.collection("deletedCustomers").get(),
    userRef.collection("deletedAppointments").get(),
  ]);
  const deletedCustomerIds = new Set(
    deletedCustomers.docs.map((document) => document.id),
  );
  const deletedAppointmentIds = new Set(
    deletedAppointments.docs.map((document) => document.id),
  );

  return {
    customers: customers.docs
      .filter((document) => !deletedCustomerIds.has(document.id))
      .map((document) => {
        const value = document.data();
        return {id: document.id, name: value.name, phone: value.phone};
      }),
    appointments: appointments.docs
      .filter((document) => {
        const value = document.data();
        return !deletedAppointmentIds.has(document.id) &&
          !deletedCustomerIds.has(value.customerId);
      })
      .map((document) => {
        const value = document.data();
        return {
          id: document.id,
          date: value.date,
          time: value.time,
          customerId: value.customerId,
          service: value.service,
        };
      }),
    deletedCustomerIds: [...deletedCustomerIds],
    deletedAppointmentIds: [...deletedAppointmentIds],
  };
});

export const syncAccountData = onCall({region}, async (request) => {
  const uid = requireUserId(request);
  const data = asRecord(request.data, "Senkronizasyon verisi");
  const customers = parseCustomers(data.customers);
  const appointments = parseAppointments(data.appointments);
  const deletedCustomerIds = parseIds(
    data.deletedCustomerIds,
    "Silinen müşteri",
  );
  const deletedAppointmentIds = parseIds(
    data.deletedAppointmentIds,
    "Silinen randevu",
  );

  const userRef = db.collection("users").doc(uid);
  const customerRef = userRef.collection("customers");
  const appointmentRef = userRef.collection("appointments");
  const deletedCustomerRef = userRef.collection("deletedCustomers");
  const deletedAppointmentRef = userRef.collection("deletedAppointments");
  const operations: Array<(batch: WriteBatch) => void> = [];
  const cascadedAppointmentIds = new Set(deletedAppointmentIds);

  for (const id of deletedCustomerIds) {
    operations.push((batch) => batch.delete(customerRef.doc(id)));
    operations.push((batch) =>
      batch.set(deletedCustomerRef.doc(id), {
        deletedAt: FieldValue.serverTimestamp(),
      })
    );
    const related = await appointmentRef.where("customerId", "==", id).get();
    for (const appointment of related.docs) {
      cascadedAppointmentIds.add(appointment.id);
    }
  }
  for (const id of cascadedAppointmentIds) {
    operations.push((batch) => batch.delete(appointmentRef.doc(id)));
    operations.push((batch) =>
      batch.set(deletedAppointmentRef.doc(id), {
        deletedAt: FieldValue.serverTimestamp(),
      })
    );
  }
  await commitOperations(operations);

  const skippedCustomers = await saveCustomersWithoutResurrection(
    uid,
    customers,
  );
  const skippedAppointments = await saveAppointmentsWithoutResurrection(
    uid,
    appointments,
  );
  const allDeletedCustomerIds = new Set([
    ...deletedCustomerIds,
    ...skippedCustomers,
    ...skippedAppointments.deletedCustomerIds,
  ]);
  const allDeletedAppointmentIds = new Set([
    ...cascadedAppointmentIds,
    ...skippedAppointments.deletedAppointmentIds,
  ]);
  return {
    customersSynced: customers.length,
    appointmentsSynced: appointments.length,
    deletedCustomerIds: [...allDeletedCustomerIds],
    deletedAppointmentIds: [...allDeletedAppointmentIds],
  };
});

export const sendAppointmentReminder = onCall(
  {region, secrets: [whatsappAccessToken]},
  async (request) => {
    requireAdministrator(request);
    const data = asRecord(request.data, "Mesaj verisi");
    const recipient = requiredText(data.phone, "Telefon numarası", 16);
    if (!/^[1-9]\d{7,14}$/.test(recipient)) {
      throw new HttpsError(
        "invalid-argument",
        "Telefon numarası ülke koduyla birlikte geçerli E.164 biçiminde olmalı.",
      );
    }

    const name = requiredText(data.customerName, "Müşteri adı", 200);
    const date = requiredText(data.appointmentDate, "Randevu tarihi", 40);
    const time = requiredText(data.appointmentTime, "Randevu saati", 5);
    const service = requiredText(data.service, "İşlem bilgisi", 1000);
    const numberId = phoneNumberId.value().trim();
    const approvedTemplate = templateName.value().trim();
    const language = templateLanguage.value().trim();
    const version = graphApiVersion.value().trim();

    if (!numberId || !approvedTemplate || !language) {
      throw new HttpsError(
        "failed-precondition",
        "WhatsApp telefon numarası ve Meta onaylı şablon sunucuda yapılandırılmalı.",
      );
    }
    if (!/^\d+$/.test(numberId) ||
        !/^[a-z0-9_]{1,512}$/.test(approvedTemplate) ||
        !/^v\d+\.\d+$/.test(version)) {
      throw new HttpsError(
        "failed-precondition",
        "WhatsApp Cloud API sunucu ayarları geçersiz.",
      );
    }
    const accessToken = whatsappAccessToken.value();
    if (!accessToken) {
      throw new HttpsError(
        "failed-precondition",
        "WhatsApp erişim anahtarı sunucu gizlisi olarak tanımlanmamış.",
      );
    }

    const response = await fetch(
      `https://graph.facebook.com/${version}/${numberId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          recipient_type: "individual",
          to: recipient,
          type: "template",
          template: {
            name: approvedTemplate,
            language: {code: language},
            components: [{
              type: "body",
              parameters: [
                {type: "text", text: name},
                {type: "text", text: date},
                {type: "text", text: time},
                {type: "text", text: service},
              ],
            }],
          },
        }),
      },
    );
    const result = await response.json() as {
      error?: {code?: number; message?: string};
      messages?: Array<{id?: string}>;
    };

    if (!response.ok) {
      logger.error("Meta WhatsApp API rejected a reminder", {
        httpStatus: response.status,
        metaErrorCode: result.error?.code,
      });
      throw new HttpsError(
        "failed-precondition",
        result.error?.message ?? "Meta WhatsApp API mesajı reddetti.",
      );
    }

    return {messageId: result.messages?.[0]?.id ?? null};
  },
);

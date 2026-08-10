import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "jsr:@supabase/supabase-js@2/cors";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

class RequestError extends Error {
  status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const body = await request.json();
    const email = String(body.email || "").trim().toLowerCase();
    const password = String(body.password || "");
    const username = String(body.username || "").trim();
    const registrationCode = String(body.registrationCode || "");
    const adminCreate = body.adminCreate === true;

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new RequestError("อีเมลไม่ถูกต้อง");
    if (username.length < 2 || username.length > 50) throw new RequestError("Username ต้องยาว 2-50 ตัวอักษร");
    if (password.length < 8) throw new RequestError("รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร");
    if (!adminCreate && !registrationCode) throw new RequestError("กรุณากรอกรหัสสมัครจากครู");

    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
    const secretKey = secretKeys.default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secretKey) throw new RequestError("Server is missing its Supabase secret key", 500);

    const admin = createClient(Deno.env.get("SUPABASE_URL") || "", secretKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    let effectiveRegistrationCode = registrationCode;
    if (adminCreate) {
      const authHeader = request.headers.get("Authorization") || "";
      const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
      if (!token) throw new RequestError("กรุณาเข้าสู่ระบบผู้ดูแล", 401);

      const { data: userData, error: userError } = await admin.auth.getUser(token);
      if (userError || !userData.user) throw new RequestError("เซสชันผู้ดูแลไม่ถูกต้อง", 401);

      const { data: profile, error: profileError } = await admin
        .from("profiles")
        .select("role")
        .eq("id", userData.user.id)
        .single();
      if (profileError || profile?.role !== "admin") {
        throw new RequestError("บัญชีนี้ไม่มีสิทธิ์เพิ่มนักเรียน", 403);
      }

      const { data: serviceRegistrationCode, error: codeError } = await admin
        .rpc("internal_registration_code_for_service_role");
      if (codeError || !serviceRegistrationCode) {
        throw new RequestError("ไม่สามารถเตรียมบัญชีนักเรียนได้", 500);
      }
      effectiveRegistrationCode = String(serviceRegistrationCode);
    }

    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        username,
        full_name: String(body.fullname || "").trim(),
        class_name: String(body.cls || "").trim(),
        student_no: String(body.no || "").trim(),
        registration_code: effectiveRegistrationCode,
      },
    });
    if (error) throw error;
    return json({ ok: true, userId: data.user.id }, 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : "สมัครสมาชิกไม่สำเร็จ";
    const status = error instanceof RequestError ? error.status : 400;
    return json({ error: message }, status);
  }
});

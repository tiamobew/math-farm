import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "jsr:@supabase/supabase-js@2/cors";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const body = await request.json();
    const email = String(body.email || "").trim().toLowerCase();
    const password = String(body.password || "");
    const username = String(body.username || "").trim();
    const registrationCode = String(body.registrationCode || "");

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error("อีเมลไม่ถูกต้อง");
    if (username.length < 2 || username.length > 50) throw new Error("Username ต้องยาว 2-50 ตัวอักษร");
    if (password.length < 8) throw new Error("รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร");
    if (!registrationCode) throw new Error("กรุณากรอกรหัสสมัครจากครู");

    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
    const secretKey = secretKeys.default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!secretKey) throw new Error("Server is missing its Supabase secret key");

    const admin = createClient(Deno.env.get("SUPABASE_URL") || "", secretKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        username,
        full_name: String(body.fullname || "").trim(),
        class_name: String(body.cls || "").trim(),
        student_no: String(body.no || "").trim(),
        registration_code: registrationCode,
      },
    });
    if (error) throw error;
    return json({ ok: true, userId: data.user.id }, 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : "สมัครสมาชิกไม่สำเร็จ";
    return json({ error: message }, 400);
  }
});

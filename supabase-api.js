(function () {
  "use strict";

  const cfg = window.MATH_FARM_SUPABASE || {};
  const enabled = Boolean(
    window.supabase && cfg.url && cfg.publishableKey &&
    !String(cfg.publishableKey).startsWith("PASTE_")
  );
  const client = enabled
    ? window.supabase.createClient(cfg.url, cfg.publishableKey, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
      })
    : null;

  const ok = data => ({ ok: true, ...(data || {}) });
  const fail = error => {
    const message = String(error?.message || error || "เชื่อมต่อ Supabase ไม่สำเร็จ")
      .replace(/^.*AUTH_REQUIRED.*$/i, "กรุณาเข้าสู่ระบบอีกครั้ง");
    return { ok: false, error: message, code: /jwt|session|auth_required/i.test(message) ? "AUTH_REQUIRED" : undefined };
  };
  const unwrap = result => {
    if (result.error) throw result.error;
    return result.data;
  };
  const normalizeUsername = value => String(value || "").trim().toLowerCase().normalize("NFKC");
  async function usernameEmail(username) {
    const bytes = new TextEncoder().encode(normalizeUsername(username));
    const digest = await crypto.subtle.digest("SHA-256", bytes);
    const hex = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, "0")).join("");
    return `student-${hex.slice(0, 40)}@students.math-farm.app`;
  }
  async function requireAdmin() {
    const profile = unwrap(await client.rpc("get_my_profile"));
    if (!profile || profile.role !== "admin") throw new Error("บัญชีนี้ไม่มีสิทธิ์ผู้ดูแล");
    return profile;
  }
  const mapProfile = row => ({
    username: row.username,
    fullname: row.full_name,
    cls: row.class_name,
    no: row.student_no,
    color: row.color,
    charName: row.character_name,
    points: Number(row.points || 0),
    coins: Number(row.coins || 0),
    pets: row.pets || {},
    decor: row.decor || {},
    createdAt: row.created_at,
    role: row.role
  });

  async function call(action, p = {}) {
    if (!enabled) return fail("ยังไม่ได้ตั้งค่า Supabase publishable key");
    try {
      switch (action) {
        case "register": {
          const username = String(p.username || "").trim();
          const email = String(p.email || "").trim().toLowerCase();
          const { data, error } = await client.functions.invoke("register-student", { body: {
            email, password: p.password, username,
            fullname: String(p.fullname || "").trim(),
            cls: String(p.cls || "").trim(), no: String(p.no || "").trim(),
            registrationCode: String(p.registrationCode || "")
          } });
          if (error) {
            let message = error.message;
            try { message = (await error.context.json()).error || message; } catch (_) {}
            throw new Error(message);
          }
          if (!data?.ok) throw new Error(data?.error || "สมัครสมาชิกไม่สำเร็จ");
          return ok();
        }
        case "login": {
          const email = String(p.email || p.username || "").trim().toLowerCase();
          unwrap(await client.auth.signInWithPassword({ email, password: p.password }));
          const user = unwrap(await client.rpc("get_my_profile"));
          if (!user) throw new Error("ไม่พบข้อมูลผู้เล่น");
          return ok({ user });
        }
        case "getProfile": {
          const user = unwrap(await client.rpc("get_my_profile"));
          return user ? ok({ user }) : fail("ไม่พบข้อมูลผู้เล่น");
        }
        case "saveCharacter": {
          const user = unwrap(await client.rpc("save_character", { p_color: p.color, p_name: p.name }));
          return ok({ user });
        }
        case "getMissions":
          return ok(unwrap(await client.rpc("get_mission_dashboard")));
        case "leaderboard":
          return ok({ users: unwrap(await client.rpc("get_leaderboard")) || [] });
        case "getFarm":
          return ok(unwrap(await client.rpc("get_farm")));
        case "saveFarmState": {
          const farmState = unwrap(await client.rpc("save_farm_state", { p_state: p.state || {} }));
          return ok({ farmState });
        }
        case "getQuestions":
          return ok({ questions: unwrap(await client.rpc("list_question_prompts")) || [] });
        case "answerQuestion":
          return ok(unwrap(await client.rpc("submit_answer", { p_question_id: p.questionId, p_answer: p.answer })));
        case "buyPet":
        case "buyDecor": {
          const type = action === "buyPet" ? "pets" : "decor";
          const id = action === "buyPet" ? p.petId : p.decorId;
          return ok(unwrap(await client.rpc("purchase_item", { p_type: type, p_item_id: id })));
        }
        case "completeMission":
          return ok(unwrap(await client.rpc("complete_mission", { p_mission_id: p.missionId, p_photo: p.photo || null })));
        case "adminAuth": {
          unwrap(await client.auth.signInWithPassword({ email: p.email, password: p.password }));
          await requireAdmin();
          return ok();
        }
        case "adminListUsers": {
          await requireAdmin();
          const rows = unwrap(await client.from("profiles").select("*").eq("role", "student").order("created_at"));
          return ok({ users: (rows || []).map(mapProfile) });
        }
        case "adminUpdateUser": {
          await requireAdmin();
          if (p.resetPass) throw new Error("การเปลี่ยนรหัสผ่านผู้เรียนให้ทำจาก Supabase Auth > Users");
          const patch = {};
          if (p.fullname !== undefined) patch.full_name = String(p.fullname);
          if (p.cls !== undefined) patch.class_name = String(p.cls);
          if (p.no !== undefined) patch.student_no = String(p.no);
          if (p.points !== undefined) patch.points = Math.max(0, Number(p.points) || 0);
          if (p.coins !== undefined) patch.coins = Math.max(0, Number(p.coins) || 0);
          unwrap(await client.from("profiles").update(patch).ilike("username", p.username).eq("role", "student"));
          return ok();
        }
        case "adminDeleteUser":
          unwrap(await client.rpc("admin_delete_user", { p_username: p.username }));
          return ok();
        case "adminListMissions": {
          const rows = unwrap(await client.from("missions").select("id,icon,title,points").order("sort_order"));
          return ok({ missions: rows || [] });
        }
        case "adminSaveMission": {
          await requireAdmin();
          unwrap(await client.from("missions").upsert({ ...p.mission, active: true }, { onConflict: "id" }));
          return ok();
        }
        case "adminDeleteMission":
          unwrap(await client.from("missions").update({ active: false }).eq("id", p.id));
          return ok();
        case "adminListQuestions": {
          await requireAdmin();
          const rows = unwrap(await client.from("questions").select("id,question,answer,coins,subject").order("sort_order"));
          return ok({ questions: rows || [] });
        }
        case "adminSaveQuestion":
          unwrap(await client.from("questions").upsert({ ...p.question, active: true }, { onConflict: "id" }));
          return ok();
        case "adminBulkAddQuestions": {
          const stamp = Date.now();
          const rows = (p.items || []).map((q, i) => ({
            id: `q${stamp + i}`, question: String(q.question), answer: String(q.answer),
            coins: Number(q.coins) || 25, subject: q.subject || "คณิตศาสตร์", active: true
          }));
          if (rows.length) unwrap(await client.from("questions").insert(rows));
          return ok({ added: rows.length });
        }
        case "adminDeleteQuestion":
          unwrap(await client.from("questions").update({ active: false }).eq("id", p.id));
          return ok();
        case "adminListShop": {
          const rows = unwrap(await client.from("shop_items").select("type,id,name,emoji,price").order("type").order("sort_order"));
          return ok({ shop: rows || [] });
        }
        case "adminSaveShopPrice": {
          const row = unwrap(await client.from("shop_items").update({ price: Number(p.price) }).eq("type", p.type).eq("id", p.id).select("type,id,name,emoji,price").single());
          return ok({ item: row });
        }
        case "adminLog": {
          await requireAdmin();
          const rows = unwrap(await client.from("mission_completions")
            .select("mission_id,points_awarded,completed_on,completed_at,evidence_data_url,profiles!inner(username),missions!inner(title)")
            .order("completed_at", { ascending: false }).limit(1000));
          return ok({ log: (rows || []).map(x => ({
            username: x.profiles.username, missionId: x.mission_id, missionTitle: x.missions.title,
            points: x.points_awarded, date: x.completed_on, at: x.completed_at, photo: x.evidence_data_url || ""
          })) });
        }
        default:
          throw new Error(`ไม่รองรับคำสั่ง ${action}`);
      }
    } catch (error) {
      return fail(error);
    }
  }

  function subscribe(onChange) {
    if (!enabled) return null;
    return client.channel("math-farm-live")
      .on("postgres_changes", { event: "*", schema: "public", table: "missions" }, onChange)
      .on("postgres_changes", { event: "*", schema: "public", table: "questions" }, onChange)
      .on("postgres_changes", { event: "*", schema: "public", table: "shop_items" }, onChange)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "profiles" }, onChange)
      .subscribe();
  }

  window.supabaseApi = Object.freeze({
    enabled,
    client,
    call,
    signOut: () => enabled ? client.auth.signOut() : Promise.resolve(),
    subscribe
  });
})();

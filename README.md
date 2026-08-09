# ฟาร์มคณิต — รุ่น GitHub Pages

รุ่นนี้เปิดเล่นได้จากเว็บแบบไฟล์สแตติก เหมาะสำหรับเผยแพร่ด้วย GitHub Pages

## การบันทึกข้อมูลออนไลน์

โปรเจกต์เตรียมเชื่อมกับ Supabase project `mifxyolxisssbtqmoacm` แล้ว ข้อมูลผู้เล่น คะแนน เหรียญ ฟาร์ม โจทย์ ภารกิจ ร้านค้า และประวัติภารกิจจะอยู่ใน PostgreSQL และอัปเดตข้ามอุปกรณ์ผ่าน Realtime

1. คัดลอก Publishable key จาก Supabase Dashboard > Connect ไปใส่ใน `supabase-config.js`
2. ล็อกอิน Supabase CLI แล้วรัน `npm run supabase -- link --project-ref mifxyolxisssbtqmoacm`
3. รัน `npm run supabase -- db push` เพื่อลง migration ใน `supabase/migrations`
4. Deploy Edge Function `register-student` เพื่อให้บัญชีนักเรียนถูกยืนยันอัตโนมัติและไม่ส่งอีเมลยืนยัน (`npm run supabase -- functions deploy register-student --no-verify-jwt`)

หน้า Admin อยู่ที่ `admin.html` และใช้ Supabase Auth แทน PIN ที่ฝังในหน้าเว็บ บัญชี `tiamobew@gmail.com` จะได้รับบทบาท admin จาก migration

หน้าเว็บใช้เฉพาะ Publishable key ซึ่งเปิดเผยใน browser ได้ตามการออกแบบของ Supabase ห้ามใส่ Secret key หรือ `service_role` ลงในไฟล์หน้าเว็บ

หากยังไม่ได้ใส่ Publishable key เกมจะถอยกลับไปใช้ `localStorage` ชั่วคราว แต่ข้อมูลจะยังไม่ข้ามอุปกรณ์

## เปิด GitHub Pages

1. สร้าง repository ใหม่ใน GitHub
2. อัปโหลดไฟล์ทั้งหมดในโฟลเดอร์นี้ไปที่ branch `main`
3. เปิด **Settings → Pages**
4. ที่ **Build and deployment** เลือก **Deploy from a branch**
5. เลือก branch `main` และโฟลเดอร์ `/ (root)` แล้วกด **Save**
6. รอประมาณ 1–3 นาที แล้วเปิด URL ที่ GitHub แสดง

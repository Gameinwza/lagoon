# Mac Dynamic Island

แอปเล็กๆ ที่แสดง "Dynamic Island" ตรงรอยบากจอ Mac แสดงเพลงที่กำลังเล่นจาก **Spotify** หรือ **Apple Music**

- ย่อ: ปกเพลง + แท่งเสียงขยับ
- เอาเมาส์ไปชี้: ขยายเป็นการ์ด มีชื่อเพลง ศิลปิน แถบเวลา และปุ่ม ก่อนหน้า / เล่น-หยุด / ถัดไป

## Build & run

```sh
./build.sh
open DynamicIsland.app
```

ครั้งแรกที่เปิดเพลง macOS จะถามสิทธิ์ให้ควบคุม Spotify/Music ให้กด OK
(ตั้งค่าภายหลังได้ที่ System Settings → Privacy & Security → Automation)

ปิดแอป: `pkill DynamicIsland`

## ข้อจำกัด

- รองรับเฉพาะ Spotify และ Music ยังไม่รองรับคลิปในเบราว์เซอร์ (YouTube) เพราะ macOS ไม่เปิดให้แอปภายนอกอ่านข้อมูล Now Playing ของระบบ
- ต้องใช้ macOS 14 ขึ้นไป

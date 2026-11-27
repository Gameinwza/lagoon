# Mac Dynamic Island

แอปเล็กๆ ที่แสดง "Dynamic Island" ตรงรอยบากจอ Mac แสดงเพลงหรือคลิปที่กำลังเล่นจาก **Spotify**, **Apple Music** หรือ **YouTube** ใน Chrome / Brave / Safari

- ย่อ: ปกเพลง + แท่งเสียงขยับ
- เอาเมาส์ไปชี้: ขยายเป็นการ์ด มีปกเพลง ชื่อเพลง ศิลปิน แถบเวลา และปุ่ม ก่อนหน้า / เล่น-หยุด / ถัดไป
- กดที่ปกหรือชื่อเพลง: เปิดหน้าเพลงนั้นใน Spotify / Music
- ถอด Bluetooth (AirPods, หูฟัง, เมาส์, คีย์บอร์ด): แสดงแจ้งเตือน 3 วินาที
- ไอคอนเล็กๆ บอกว่ามีอุปกรณ์ Bluetooth อะไรต่ออยู่ พร้อม % แบต (ชี้ค้างเพื่อดูแบตหูซ้าย/ขวา/กล่อง)
- เปิดเองอัตโนมัติตอนล็อกอิน (ปิดได้ที่ System Settings → General → Login Items)

## Build & run

```sh
./build.sh
cp -R DynamicIsland.app /Applications/
open /Applications/DynamicIsland.app
```

ครั้งแรกที่เปิดเพลง macOS จะถามสิทธิ์ให้ควบคุม Spotify/Music ให้กด OK
(ตั้งค่าภายหลังได้ที่ System Settings → Privacy & Security → Automation)

ปิดแอป: `pkill DynamicIsland`

## YouTube

ต้องเปิดให้เบราว์เซอร์รับ JavaScript จาก AppleScript ก่อน ไม่งั้นจะเห็นแค่ชื่อคลิป ไม่มีแถบเวลาและปุ่มควบคุม

- **Chrome / Brave:** เมนู View → Developer → Allow JavaScript from Apple Events
- **Safari:** Settings → Advanced → เปิด "Show features for web developers" แล้วไปที่เมนู Develop → Allow JavaScript from Apple Events

## ข้อจำกัด

- รองรับ YouTube เฉพาะหน้าดูคลิป (`youtube.com/watch`) ใน Chrome, Brave และ Safari
- ต้องใช้ macOS 14 ขึ้นไป

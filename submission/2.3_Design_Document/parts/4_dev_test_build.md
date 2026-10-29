## 5. การพัฒนา

### 5.1 เครื่องมือและสคริปต์

กลุ่มเขียนสคริปต์ให้ทุกขั้นตอนสั่งจาก Command Prompt ได้ด้วยคำสั่งเดียว (ไม่ต้องคลิกในหน้าต่าง Vivado จึงทำซ้ำได้เหมือนเดิมทุกครั้ง):

| คำสั่ง | ทำอะไร |
|---|---|
| `tools\build.bat game` | สร้าง `game\build\top_tetris.bit` (synthesis, place, route) และพิมพ์ WNS, รายงานทรัพยากร |
| `tools\program.bat game` | โหลดบิตลงบอร์ด (ชั่วคราว หายเมื่อปิดไฟ) |
| `tools\sim.bat tb_versus` | รัน testbench แล้วดูผล TEST PASSED |
| `python tools\make_game_media.py` | สร้างไฟล์สื่อ `media\game_media.bin` จากรายการใน `tools\media_plan.py` |
| `tools\flash_media.bat media\game_media.bin` | เขียนไฟล์สื่อลงแฟลชที่ 0x100000 (ครั้งเดียวต่อบอร์ด) |
| `tools\load_into_builder.bat game` | ใส่รายชื่อไฟล์และขาลงใน FPGA Builder ของ TA |
| `tools\vivado_gui.bat game` | สร้างโปรเจกต์ Vivado แล้วเปิดหน้าต่าง (ใช้ดู schematic) |
| `python tools\fake_opponent.py COM3` | ให้คอมพิวเตอร์เล่นเป็นบอร์ดคู่แข่งผ่าน USB (SW7 ขึ้น) |

ทุกการออกแบบ (ตัวเกมและวงจรทดสอบแต่ละชุด) อธิบายด้วยไฟล์ข้อความ 2 ไฟล์: `project.txt` (entity บนสุด + ไฟล์ VHDL ตามลำดับ compile)
และ `pins.xdc` (ขาของแต่ละ port) สคริปต์ทุกตัวอ่านจากไฟล์ชุดเดียวกัน ใช้ git เก็บประวัติทุกการแก้ไข

### 5.2 พัฒนาเป็นชั้น

![ไทม์ไลน์การทำงาน](../figures/fig_timeline.png)

| ชั้น | เพิ่มอะไร | LUT | ผลบนบอร์ดจริง |
|---|---|---|---|
| 0. วงจรทดสอบ | VGA, หาขา J5, UART, เชื่อมบอร์ด, ตรวจขา UART | - | ผ่าน (15-16 ต.ค.) |
| 1. main | เกม + โหมดต่อสู้ | 3,496 (44 %) | เล่น 2 บอร์ดกับเพื่อนได้ (19 ต.ค.) |
| 2. chaos | ภารกิจ, การโจมตี, โบนัส | 6,200 (78 %) | เล่นได้ ปรับตามความเห็น 2 รอบ |
| 3. media | ทดสอบ 06 อ่านแฟลช → สื่อในเกม | 6,797 (85 %) | ทำงานครบ (21 ต.ค.) |

แต่ละชั้นทำเสร็จและทดสอบบนบอร์ดก่อนเริ่มชั้นถัดไป ถ้าชั้นใหม่มีปัญหาก็ยังมีชั้นก่อนหน้าที่ใช้งานได้เสมอ
(เก็บแยกเป็น branch ของ git: `main`, `chaos`, `media`)

### 5.3 ปัญหาที่พบและวิธีแก้

| ปัญหา | สาเหตุ | วิธีแก้ |
|---|---|---|
| UART จาก PC ไม่ทำงานตามคู่มือ | ขา TX/RX ในคู่มือสลับกัน | สร้างวงจรทดสอบ 05 ลองทั้งสองแบบ → สลับขา |
| สวิตช์โยกครั้งเดียวนับหลายครั้ง และค่าเปลี่ยนเองเมื่อโยกค้างครึ่งทาง | สวิตช์เด้ง, ขาลอย | `switch_filter` แบบ integrator + PULLDOWN ทุกขา |
| เริ่มเกมใหม่ทันทีโดยไม่ตั้งใจหลังจบเกม | ยังกดปุ่มค้างจากเกมก่อน | เวลาพัก 1.5 วินาทีหลังจบเกม (`can_start`) |
| ใส่สื่อแล้ววงจรวางไม่ลงชิป (7,566 LUT = 95 %) | ข้อความแต่ละบรรทัดมี ROM ฟอนต์ของตัวเอง | `text_multi`: ROM ฟอนต์ตัวเดียวต่อตัววาด, ลูกบอลขยับทีละลูก → 6,972 LUT |
| frame buffer 19,200 ไบต์ ใช้ block RAM 8 ก้อน | Vivado แบ่ง array ขนาดนี้ไม่ประหยัด | แบ่งเป็น 5 ก้อนก้อนละ 4,096 ไบต์ด้วยมือ + attribute `ram_style = block` |
| ภาพวิดีโอขาดเป็นช่วง | run ยาว 128 พิกเซลแต่ไบต์มาทุก 17 รอบนาฬิกา | สัญญาณ `hold` หยุดแฟลชระหว่างที่ตัวถอดยังไม่ว่าง |
| testbench ของวงจรทั้งหมดรันไม่จบ | โมเดลจำลองของ `STARTUPE2` ไม่หยุดเอง | generic `USE_STARTUP => false` ใน testbench |
| สคริปต์เขียนแฟลชเงียบและไม่ทำอะไร | วงเล็บในข้อความ echo ภายใน `if ( ... )` ของ batch file | escape เป็น `^(` `^)` |
| Jump scare Foxy เล็กกลางจอ | วิดีโอ 4:3 อยู่ในกรอบ 16:9 | ตั้งค่า `crop` ตัดเฉพาะส่วน 4:3 ก่อนย่อ |
| เต็มชิปอีกครั้งหลังแก้หลายรอบ | ฟีเจอร์ที่ไม่ใช้แล้วยังกินวงจร | ลบการโจมตีแมว ROM เดิม และโน้ตที่ไม่ใช้ → 6,797 LUT (85 %) |

### 5.4 การปรับตามความเห็นของผู้เล่น

หลังเล่น CHAOS บนบอร์ดจริงรอบแรก กลุ่มรวบรวมความเห็นแล้วแก้:

| ความเห็น | สิ่งที่เปลี่ยน |
|---|---|
| ตัวนับเวลา "ภารกิจถัดไป" ทำให้ไม่ลุ้น | ซ่อนแผงจนกว่าจะมีภารกิจ ไม่แสดงเวลานับถอยหลัง |
| อยากได้ภารกิจเลขฐานสิบหกด้วย | เพิ่มภารกิจ HEX |
| โซนเขียวกว้างเท่าเดิมทุกครั้ง | สุ่มความกว้างทุกภารกิจ |
| ทุกอย่างที่มีเวลาควรสุ่ม | ทุกระยะเวลาเป็นช่วงสุ่ม (`rand_range`) |
| ไม่ทำภารกิจเลย เล่นเตตริสอย่างเดียวก็ได้ | เพิ่มการโจมตี LOCK: ล็อกปุ่มจนกว่าจะทำภารกิจ |
| ขยะเข้ามา 8 แถวพร้อมกันโหดเกิน | รับได้ครั้งละ 3-5 แถว |
| FREEZE นานเกิน, ลูกบอลน้อยเกิน, BLIND ยังเห็นบล็อกสีเทา | ปรับเวลา 3-5 วิ, ลูกบอล 5-10 ลูก, ไม่วาดบล็อกเลย |
| SINK เกิดตอนบล็อกถัดไปล็อก ช้าเกิน | SINK ทันทีจาก S_PLAY (เพิ่ม S_SINK_CHK) |

## 6. การทดสอบ

### 6.1 แนวทาง: ออกแบบจากบนลงล่าง ทดสอบจากล่างขึ้นบน

![การจับคู่ระดับการออกแบบกับระดับการทดสอบ](../figures/fig_vmodel.png)

ทุกโมดูลถูกทดสอบด้วย **simulation** ก่อนโหลดลงบอร์ดเสมอ (การ build หนึ่งครั้งใช้หลายนาที
แต่ simulation เห็นสัญญาณทุกเส้นในทุกรอบนาฬิกา) จากนั้นทดสอบฮาร์ดแวร์ทีละส่วนด้วยวงจรทดสอบเล็กๆ
และสุดท้ายเล่นจริงกับเพื่อน

### 6.2 Testbench (การจำลอง)

testbench ทุกตัว **ตรวจผลเอง** และพิมพ์ `TEST PASSED` หรือบอกว่าผิดตรงไหน (ไม่ต้องนั่งดูกราฟสัญญาณ) รันด้วย `tools\sim.bat <ชื่อ>`

| testbench | ทดสอบอะไร | ผล |
|---|---|---|
| `tb_uart_loop` | uart_tx ส่งเข้า uart_rx: ทุกไบต์ที่ส่งกลับออกมาเหมือนเดิม | ผ่าน |
| `tb_vga_frame` | จังหวะ VGA ครบเฟรม + บันทึกภาพเป็น PNG | ผ่าน |
| `tb_uart_probe` | วงจรทดสอบ 05 กับการต่อสายทั้งสองแบบ | ผ่าน |
| `tb_switch_filter` | ตัวกรองสวิตช์กับสัญญาณเด้ง | ผ่าน |
| `tb_tetris_core` | หุ่นยนต์เล่นทั้งเกมจนแพ้; ตรวจว่าจำนวนช่องบนกระดานไม่หาย/ไม่เกินทุกครั้งที่ล็อกและล้าง | ผ่าน |
| `tb_versus` | สองบอร์ด (core + link) เล่นกันโดยหุ่นยนต์สองตัว: START ข้ามบอร์ด, ขยะ, WIN/LOSE, LINKED, เวลาพักหลังจบเกม | ผ่าน |
| `tb_tetris_frame` | วงจรทั้งหมด; บันทึกภาพหน้าจอเกมและหน้าจอ WIN! | ผ่าน |
| `tb_chaos` | ทำภารกิจ → การโจมตีข้ามสาย → ผลบนอีกบอร์ด, LOCK | ผ่าน |
| `tb_chaos_core` | FREEZE, SPEED, CURSED, I-PIECE, SINK | ผ่าน |
| `tb_chaos_frame` | ภาพหน้าจอ: CHAOS เปิด + ขยะรอ, แผงภารกิจ + BLIND, FLIP + ลูกบอล | ผ่าน |
| `tb_flash_read` | วงจรทดสอบ 06 กับแฟลชจำลอง | ผ่าน |
| `tb_media_engine` | เครื่องเล่นสื่อ: เสียงทุกตัวอย่าง, ภาพ delta, โหมด panel, over, sprite | ผ่าน |
| `tb_media_ctrl` | ลำดับการเล่น: เพลง, การโจมตี, ชนะ/แพ้, เล่นเพลงต่อ | ผ่าน |

![ภาพจาก tb_chaos_frame: แผงภารกิจ "SET IN BINARY: 229" และแบนเนอร์ INCOMING: BLIND (บล็อกที่วางแล้วล่องหน)](../figures/screenshot_chaos_task.png)

### 6.3 วงจรทดสอบฮาร์ดแวร์

ก่อนเขียนเกม กลุ่มสร้างวงจรเล็กๆ 6 ชุด (โฟลเดอร์ `tests\`) แต่ละชุดทดสอบฮาร์ดแวร์อย่างเดียว ถ้าเกมมีปัญหาภายหลัง
ก็รู้ว่าไม่ใช่ที่ขาหรือสาย

| วงจรทดสอบ | ทดสอบอะไร | ผลบนบอร์ดจริง |
|---|---|---|
| 01 vga_bars | แถบสี, ไล่ระดับสี, ตาราง, สี่เหลี่ยมเด้ง | ผ่าน: สีครบ 4,096 สี, ขอบภาพตรง |
| 02 j5_pin_finder | ขา FPGA ใดอยู่ที่ขาไหนของ J5 | ผ่าน: แผนที่ขา J5 ครบ 16 ขา |
| 03 uart_echo | คุยกับ PC ผ่าน USB | ผ่าน (หลังสลับขา) |
| 04 board_link | สองบอร์ดคุยกันผ่านสายจัมเปอร์ | ผ่าน (เป็นพื้นฐานของ versus_link) |
| 05 uart_probe | ขา USB-UART ขาไหน TX ขาไหน RX | พบว่าคู่มือสลับขา |
| 06 flash_read | อ่านภาพ แอนิเมชัน และเสียงจากแฟลช | ผ่าน: อ่าน ID ได้, ตรวจข้อมูล 0 ไบต์ผิด ใน 83 ms, เสียงไม่ขาด, ภาพกับเสียงตรงกัน |

### 6.4 การทดสอบเล่นจริง

| วันที่ | ทดสอบ | ผล |
|---|---|---|
| 19 ต.ค. 2569 | โหมดต่อสู้บน 2 บอร์ดกับเพื่อน | เชื่อมต่อทันที (LINKED), ขยะ/ชนะ/แพ้ถูกต้อง |
| 19 ต.ค. 2569 | CHAOS รอบ 1 และ 2 | เล่นได้ทุกภารกิจ ปรับตามความเห็น (ข้อ 5.4) |
| 20 ต.ค. 2569 | วงจรทดสอบ 06 | ผ่านทุกข้อ |
| 21 ต.ค. 2569 | สื่อในเกม | เพลง, วิดีโอโจมตี, ฉากแพ้ชนะ, sprite ทำงานครบ; แก้ 4 จุด (ข้อ 5.3) |

[ใส่รูปถ่ายจริง: บอร์ดสองบอร์ดต่อสาย, จอขณะเล่น, จอขณะวิดีโอโจมตี]

### 6.5 ผลการ build สุดท้าย

* **ทรัพยากร**: LUT 6,797 / 8,000 (85 %), Slice 1,962 / 2,000 (98 %), flip-flop 3,045 (19 %),
  Block RAM 10 / 10 (100 %), DSP 3 / 20, ขา I/O 57
* **Timing**: WNS = +3.441 ns, TNS = 0: ทุกเส้นทางทำงานได้ที่ 50 MHz และยังเหลือเวลาอีก 3.4 ns จาก 20 ns
* **ไฟล์สื่อ**: 6,863,360 ไบต์ จากที่ว่าง 7 MB, โปรแกรมสร้างไฟล์ถอดรหัสทุกรายการกลับมาตรวจก่อนเขียนแฟลช

## 7. วิธีสร้างชิ้นงานซ้ำทีละขั้น

บทนี้เขียนให้คนที่มีแค่อุปกรณ์และไฟล์ในสื่อบันทึกข้อมูล ทำตามแล้วได้ชิ้นงานที่เล่นได้

### 7.1 อุปกรณ์

| อุปกรณ์ | จำนวน |
|---|---|
| บอร์ด EDGE Spartan-7 (XC7S15) พร้อมสาย USB | 2 |
| จอที่มีช่อง VGA + สาย VGA | 2 |
| หูฟังหรือลำโพงแบบมีไฟเลี้ยง (แจ็ค 3.5 มม.) | 2 (ไม่บังคับ) |
| สายจัมเปอร์ตัวเมีย-ตัวเมีย | 3 เส้น |
| คอมพิวเตอร์ Windows | 1 |

### 7.2 ติดตั้งโปรแกรม

1. **Vivado 2025.2** (ฟรี, รุ่น Standard) จาก AMD ติดตั้งที่ `D:\AMDDesignTools\2025.2` หรือใช้ Vivado ใน FPGA Builder ของ TA
   (สคริปต์หาทั้งสองที่)
2. **FPGA Builder ของ TA** (`D:\setup\FPGA_Builder_Package_V9`): มี openFPGALoader สำหรับโหลดบิตและเขียนแฟลช
3. **Python 3** + แพ็กเกจ: `python -m pip install numpy pillow pyserial`
4. **ffmpeg** (เฉพาะถ้าจะสร้างไฟล์สื่อใหม่จากวิดีโอต้นฉบับ)
5. คัดลอกโฟลเดอร์ซอร์สโค้ดไปไว้ในที่ที่ **ไม่มีช่องว่างหรือภาษาไทยในชื่อ path** (เช่น `D:\setup\assignment`)

### 7.3 สร้างไฟล์ .bit

```
cd D:\setup\assignment
tools\build.bat game
```

ใช้เวลาประมาณ 3-5 นาที เมื่อเสร็จจะพิมพ์ WNS (ต้องไม่ติดลบ) และได้ `game\build\top_tetris.bit`
(ในสื่อบันทึกข้อมูลมีไฟล์นี้ที่ build เสร็จแล้ว ข้ามขั้นนี้ได้)

ทางเลือก: ใช้ FPGA Builder ของ TA: ปิด Builder → `tools\load_into_builder.bat game` → เปิด Builder → กด Build แล้ว Program

### 7.4 สร้างและเขียนไฟล์สื่อลงแฟลช (ครั้งเดียวต่อบอร์ด)

1. ไฟล์ `media\game_media.bin` ที่สร้างเสร็จแล้วอยู่ในสื่อบันทึกข้อมูล (ถ้าจะสร้างใหม่: ใส่ไฟล์วิดีโอ/เพลง/รูปต้นฉบับตามรายการใน
   `tools\media_plan.py` ไว้ในโฟลเดอร์ `media\` แล้วรัน `python tools\make_game_media.py`)
2. ต่อบอร์ดกับคอมพิวเตอร์ ปิด FPGA Builder แล้วรัน:

```
tools\flash_media.bat media\game_media.bin
```

ใช้เวลาไม่กี่นาที ข้อมูลอยู่ในแฟลชถาวรแม้ปิดไฟ (ไม่ต้องทำซ้ำ) ทำกับทั้งสองบอร์ด
(ถ้าไม่ได้เขียนไฟล์สื่อ เกมยังเล่นได้ แค่ไม่มีเพลงและวิดีโอ)

### 7.5 โหลดเกมลงบอร์ด

```
tools\program.bat game
```

ทำกับทั้งสองบอร์ด (ไฟล์ `.bit` เดียวกัน) หรือใช้ปุ่ม Program ใน FPGA Builder
ถ้าต้องการให้บอร์ดจำเกมไว้แม้ปิดไฟ: `tools\program.bat game flash`

### 7.6 ต่อสายและเล่น

1. ต่อจอ VGA และหูฟังที่แต่ละบอร์ด
2. ต่อสายจัมเปอร์ 3 เส้นที่หัวต่อ J5 (ตรงจากขาถึงขา ไม่มีอะไรคั่น):
   บอร์ด A ขา 5 → บอร์ด B ขา 6, บอร์ด A ขา 6 → บอร์ด B ขา 5, ขา 2 ของทั้งสองบอร์ดต่อกัน (GND)
3. สวิตช์ SW7 ลง (ใช้สาย J5) SW4, SW5 ขึ้น (เพลง, เสียงเอฟเฟกต์) SW6 ขึ้นถ้าจะเล่นโหมด CHAOS (ทั้งสองบอร์ด)
4. ภายในครึ่งวินาทีทั้งสองจอขึ้น **LINKED**
5. กด **SW18** (ปุ่มกลาง) ที่บอร์ดไหนก็ได้ ทั้งสองบอร์ดเริ่มพร้อมกัน

### 7.7 ทดสอบด้วยบอร์ดเดียว (คอมพิวเตอร์เล่นเป็นคู่แข่ง)

1. SW7 ขึ้น (ใช้ USB แทนสาย J5) แล้วรัน `python tools\fake_opponent.py COM3` (COM ตามที่ Device Manager แสดง)
2. จอขึ้น LINKED พิมพ์ `s` = START, `g 3` = ขยะ 3 แถว, `l` = คู่แข่งแพ้, `x 8` / `x 9` / `x 10` = โจมตีด้วยวิดีโอ Bad Apple / OIIA / Jevil

### 7.8 แก้ปัญหา

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|---|---|---|
| จอไม่ขึ้นภาพ | ยังไม่ได้โหลดบิต, สาย VGA หลวม | โหลดใหม่, เสียบสายแน่น |
| ไม่ขึ้น LINKED | สายไม่ไขว้ TX → RX, ไม่ได้ต่อ GND, SW7 ขึ้นอยู่ | ตรวจสาย, SW7 ลง |
| ไม่มีเพลง/วิดีโอ | ยังไม่ได้เขียนไฟล์สื่อลงแฟลช, SW4 ลง | `flash_media.bat`, SW4 ขึ้น |
| ไม่มีภารกิจ CHAOS | SW6 ลง หรือยังไม่ได้เริ่มเกม | SW6 ขึ้นทั้งสองบอร์ด แล้วเริ่มเกม |
| เขียนแฟลชไม่ได้ | FPGA Builder เปิดอยู่ (ใช้สาย USB ร่วมกัน) | ปิด Builder ก่อน |
| build ไม่ผ่าน | path มีช่องว่าง/ภาษาไทย | ย้ายโฟลเดอร์ |

## 8. วิธีเล่น

| ปุ่ม | หน้าที่ |
|---|---|
| SW14 / SW20 | เลื่อนซ้าย / ขวา (กดค้างได้) |
| SW16 | หมุน |
| SW23 | ตกช้า (กดค้าง) |
| SW18 | ตกทันที / เริ่มเกม |

| สวิตช์เลื่อน (ขึ้น = เปิด) | หน้าที่ |
|---|---|
| SW2 | พักเกม |
| SW4 | เพลงและเสียงของสื่อ |
| SW5 | เสียงเอฟเฟกต์ |
| SW6 | เปิดโหมด CHAOS (เปิดทั้งสองบอร์ด) |
| SW7 | เชื่อมกับ PC ผ่าน USB แทนสาย J5 |
| SW22 SW21 SW19 SW17 SW15 SW13 SW12 SW11 | สวิตช์ภารกิจ 8 ตัว (ซ้ายสุด, บิต 7 → บิต 0) |

7-segment แสดงจำนวนแถวที่ล้าง หรือวินาทีที่เหลือขณะมีภารกิจ

**กติกา**: ล้าง 2 / 3 / 4 แถวพร้อมกัน ส่งขยะ 1 / 2 / 4 แถวไปหาคู่แข่ง (หักกับขยะที่รอเข้ามาหาเราก่อน) คนที่ถูกดันล้นจอแพ้
ในโหมด CHAOS ภารกิจโผล่ด้านขวาทุก 10-17 วินาที ทำด้วยสวิตช์ภารกิจให้ทันเวลา แล้วสุ่มได้การโจมตี (62.5 %) หรือโบนัส (37.5 %)

## 9. สรุปผล

### 9.1 ผลที่ได้เทียบกับข้อกำหนด

| ข้อกำหนด | ผล |
|---|---|
| R1 เตตริสครบกติกา | ทำได้: 7-bag, ghost, wall kick, lock delay, เลเวล, เลื่อนค้าง |
| R2 ต่อสู้ 2 บอร์ด | ทำได้: ขยะ, แถบ RIVAL, เริ่มพร้อมกัน, ชนะ/แพ้/เสมอตรงกัน |
| R3 รู้สถานะการเชื่อมต่อ | ทำได้: LINKED ภายใน 0.5 วินาที, เล่นคนเดียวได้ |
| R4 CHAOS | ทำได้: ภารกิจ 7 แบบ, การโจมตี 11 แบบ, โบนัส 3 แบบ |
| R5 เพลงและเสียง | ทำได้: เพลง 2 เพลง, เสียงเอฟเฟกต์ 12 แบบ |
| R6 วิดีโอจากแฟลช | ทำได้: วิดีโอโจมตี 3 แบบ, คลิป/รูปแพ้ 8 แบบ ชนะ 4 แบบ, sprite 2 แบบ |
| R7 ใส่ชิปได้และผ่าน timing | ทำได้: 85 % LUT, 100 % block RAM, WNS +3.4 ns |

### 9.2 สิ่งที่ได้เรียนรู้

* การออกแบบแบบ Top-Down ทำให้แบ่งงานได้ชัด และเมื่อมีปัญหาก็ไล่หาได้ทีละระดับ
* simulation ที่ตรวจผลเองช่วยประหยัดเวลามาก เพราะการ build หนึ่งครั้งใช้หลายนาที
* ฮาร์ดแวร์จริงไม่ตรงกับเอกสารเสมอไป ต้องมีวงจรทดสอบเล็กๆ เพื่อยืนยัน
* ทรัพยากรของ FPGA มีจำกัดจริง ต้องเลือกโครงสร้างที่ประหยัด (ใช้วงจรร่วมกัน, ทำงานทีละขั้นแทนพร้อมกัน)

### 9.3 ข้อจำกัดและแนวทางพัฒนาต่อ

* ชิปเต็มแล้ว (slice 98 %, block RAM 100 %): ฟีเจอร์ใหม่ต้องลดของเดิมก่อน หรือใช้ชิปที่ใหญ่กว่า
* วิดีโอมีความละเอียดเพียง 160 × 120 เพราะไม่มี RAM ภายนอก
* แนวทางต่อไป: มินิเกมเพิ่ม, เล่นได้มากกว่า 2 คน (ต่อสายแบบวง), ใช้คีย์บอร์ด PS/2

## 10. แหล่งอ้างอิง

1. EDGE Spartan 7 FPGA Development Board User Manual
2. AMD/Xilinx, *7 Series FPGAs Memory Resources User Guide* (UG473): block RAM
3. AMD/Xilinx, *7 Series FPGAs Configuration User Guide* (UG470): STARTUPE2 และการบูตจากแฟลช
4. Infineon (Cypress), *S25FL064L 64-Mbit SPI Flash Datasheet*
5. Interactive Multimedia Association, *Recommended Practices for Enhancing Digital Audio Compatibility* (IMA ADPCM), 1992
6. VGA Signal 640 × 480 @ 60 Hz Timing (tinyvga.com)
7. Tetris Guideline: 7-bag, lock delay, garbage (tetris.wiki)
8. เอกสารและแลปของรายวิชา Digital System Fundamentals in Practice

**สื่อที่ใช้ในเกม** (ใช้เพื่อการศึกษาเท่านั้น ลิขสิทธิ์เป็นของเจ้าของ):
[รายการเพลงและวิดีโอพร้อมเจ้าของ: TETORIS (Hiiragi Magnetite), Tetris theme (Korobeiniki), Bad Apple!! (Touhou / Alstroemeria Records), OIIA OIIA cat, Jevil / THE WORLD REVOLVING (Toby Fox, Deltarune), Rick Astley - Never Gonna Give You Up, FNaF 2 (Scott Cawthon), yippee cat ฯลฯ]

## ภาคผนวก ก. รายชื่อไฟล์

| โฟลเดอร์ | ไฟล์ |
|---|---|
| `game\` | `top_tetris.vhd` (บนสุด), `project.txt`, `pins.xdc`, `build\top_tetris.bit` |
| `src\common\` | `common_pkg`, `debounce`, `switch_filter`, `seg7_scan`, `vga_sync`, `uart_tx`, `uart_rx` |
| `src\game\` | `tetris_pkg`, `text_pkg`, `chaos_pkg`, `tetris_input`, `tetris_core`, `versus_link`, `chaos_task`, `chaos_fx`, `text_multi`, `chaos_render`, `tetris_render`, `tetris_sound` |
| `src\media\` | `spi_flash`, `adpcm_dec`, `media_engine`, `media_ctrl`, `media_mix` |
| `tests\01..06\` | วงจรทดสอบฮาร์ดแวร์ 6 ชุด |
| `sim\` | testbench 13 ชุด |
| `tools\` | สคริปต์ build / program / sim / flash และโปรแกรม Python สร้างไฟล์สื่อ |
| `docs\learn\` | เอกสารอธิบายโค้ดทุกบรรทัด 9 บท (ภาษาอังกฤษ) + หน้าเว็บอธิบายแบบโต้ตอบ |
| `submission\figures\vivado\` | schematic จาก Vivado ทุกโมดูล (PDF ต้นฉบับ + PNG) |

ซอร์สโค้ดทั้งหมดอยู่ในสื่อบันทึกข้อมูล โฟลเดอร์ `Source_Code` [และ GitHub: ใส่ลิงก์ถ้าเปิดสาธารณะ]

<!-- PAGEBREAK -->

## ภาคผนวก ข. ซอร์สโค้ด VHDL ทั้งหมด

ไฟล์ทั้ง 25 ไฟล์ของชิ้นงาน เรียงตามลำดับ compile ใน `game/project.txt` (package ก่อน แล้วโมดูลจากล่างขึ้นบน จบที่ `top_tetris`)
ตามด้วยไฟล์กำหนดขา `pins.xdc` รวม 5,705 บรรทัด VHDL เลขบรรทัดตรงกับที่อ้างในบทที่ 4

<!-- SOURCE: src/common/common_pkg.vhd -->
<!-- SOURCE: src/game/tetris_pkg.vhd -->
<!-- SOURCE: src/game/text_pkg.vhd -->
<!-- SOURCE: src/game/chaos_pkg.vhd -->
<!-- SOURCE: src/common/debounce.vhd -->
<!-- SOURCE: src/common/switch_filter.vhd -->
<!-- SOURCE: src/common/seg7_scan.vhd -->
<!-- SOURCE: src/common/vga_sync.vhd -->
<!-- SOURCE: src/common/uart_tx.vhd -->
<!-- SOURCE: src/common/uart_rx.vhd -->
<!-- SOURCE: src/game/tetris_input.vhd -->
<!-- SOURCE: src/game/tetris_core.vhd -->
<!-- SOURCE: src/game/versus_link.vhd -->
<!-- SOURCE: src/game/chaos_task.vhd -->
<!-- SOURCE: src/game/chaos_fx.vhd -->
<!-- SOURCE: src/game/text_multi.vhd -->
<!-- SOURCE: src/game/chaos_render.vhd -->
<!-- SOURCE: src/game/tetris_render.vhd -->
<!-- SOURCE: src/game/tetris_sound.vhd -->
<!-- SOURCE: src/media/spi_flash.vhd -->
<!-- SOURCE: src/media/adpcm_dec.vhd -->
<!-- SOURCE: src/media/media_engine.vhd -->
<!-- SOURCE: src/media/media_ctrl.vhd -->
<!-- SOURCE: src/media/media_mix.vhd -->
<!-- SOURCE: game/top_tetris.vhd -->
<!-- SOURCE: game/project.txt -->
<!-- SOURCE: game/pins.xdc -->

<!-- PAGEBREAK -->

## ภาคผนวก ค. schematic จาก Vivado ของทุกโมดูล

สร้างด้วย Vivado: Open Elaborated Design → Schematic แล้วเลือกแต่ละ instance → Export to PDF (หมุนภาพแล้ว)
ภาพในเอกสารย่อลงเพื่อให้พอดีหน้า ไฟล์ PNG ความละเอียดสูงและ PDF ต้นฉบับ (ซูมได้ไม่จำกัด) อยู่ในโฟลเดอร์ `figures/vivado`
ชื่อไฟล์คือชื่อ instance ในโค้ด (`u_core` = `tetris_core` เป็นต้น) ภาพของโมดูลย่อยชั้นที่สองมีกรอบสีน้ำเงินของโมดูลแม่ล้อมอยู่

![top_tetris (ระดับบนสุด)](../figures/vivado_png/top_preview.png)

![u_sync = vga_sync](../figures/vivado_png/u_sync_preview.png)

![u_input = tetris_input](../figures/vivado_png/u_input_preview.png)

![debounce (ใน u_input)](../figures/vivado_png/debounce_preview.png)

![u_sw = switch_filter](../figures/vivado_png/u_sw_preview.png)

![u_core = tetris_core (ภาพรวม)](../figures/vivado_png/u_core_preview.png)

![u_core = tetris_core (ซูมกลางภาพ: RTL_MUX หลายอินพุตจำนวนมาก ซึ่งเลือกแถว/บิตของกระดาน 20 × 10 ช่อง แสดงว่าทำไมโมดูลนี้ใหญ่ที่สุด)](../figures/vivado_png/u_core_zoom.png)

![u_link = versus_link](../figures/vivado_png/u_link_preview.png)

![u_tx = uart_tx (ใน u_link)](../figures/vivado_png/u_tx_preview.png)

![u_rx = uart_rx (ใน u_link)](../figures/vivado_png/u_rx_preview.png)

![u_task = chaos_task](../figures/vivado_png/u_task_preview.png)

![u_fx = chaos_fx](../figures/vivado_png/u_fx_preview.png)

![u_crender = chaos_render](../figures/vivado_png/u_crender_preview.png)

![u_text = text_multi (ใน u_crender = chaos_render)](../figures/vivado_png/u_text_preview.png)

![u_render = tetris_render](../figures/vivado_png/u_render_preview.png)

![u_media = media_engine](../figures/vivado_png/u_media_preview.png)

![u_spi = spi_flash (ใน u_media)](../figures/vivado_png/u_spi_preview.png)

![u_dec = adpcm_dec (ใน u_media)](../figures/vivado_png/u_dec_preview.png)

![u_mctrl = media_ctrl](../figures/vivado_png/u_mctrl_preview.png)

![u_mix = media_mix](../figures/vivado_png/u_mix_preview.png)

![u_sound = tetris_sound](../figures/vivado_png/u_sound_preview.png)

![u_sec = seg7_scan (instance ชื่อ u_seg)](../figures/vivado_png/u_sec_preview.png)

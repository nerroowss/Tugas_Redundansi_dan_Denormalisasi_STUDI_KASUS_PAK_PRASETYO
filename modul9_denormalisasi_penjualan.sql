-- =====================================================
-- Nama  : IKHZANIERO ARDYANA JUNIAR
-- NIM   : 264311070
-- Kelas : 1C
-- Prodi : TEKNOLOGIREKAYASA PERANGKAT LUNAK
-- Modul 9: Redundansi dan Denormalisasi
-- Studi kasus dosen: pelanggan, pesanan, detail_pesanan
-- Urutan script mengikuti urutan praktikum.
-- Catatan: DROP DATABASE menghapus database lama bernama sama.
-- =====================================================

DROP DATABASE IF EXISTS redundansi_dan_denormalisasi;
CREATE DATABASE redundansi_dan_denormalisasi;
USE redundansi_dan_denormalisasi;

-- ===== 0. SCHEMA =====
CREATE TABLE pelanggan (
    id_pelanggan INT PRIMARY KEY,
    nama_pelanggan VARCHAR(100)
);

CREATE TABLE pesanan (
    id_pesanan INT PRIMARY KEY,
    id_pelanggan INT,
    tanggal DATE,
    FOREIGN KEY (id_pelanggan) REFERENCES pelanggan(id_pelanggan)
);

CREATE TABLE detail_pesanan (
    id_detail INT PRIMARY KEY,
    id_pesanan INT,
    jumlah INT,
    harga_satuan DECIMAL(10,2),
    FOREIGN KEY (id_pesanan) REFERENCES pesanan(id_pesanan)
);

-- ===== 0. DATA CONTOH =====
INSERT INTO pelanggan (id_pelanggan, nama_pelanggan) VALUES (1,'Budi'),(2,'Siti');
INSERT INTO pesanan (id_pesanan, id_pelanggan, tanggal) VALUES (101,1,'2026-10-01'),(102,2,'2026-10-02');
INSERT INTO detail_pesanan (id_detail, id_pesanan, jumlah, harga_satuan)
VALUES (1,101,2,50000),(2,101,1,150000),(3,102,5,20000);

-- ===== TAHAP 1: EKSPLORASI JOIN (kondisi normalisasi) =====
-- Hasil: Budi 250000, Siti 100000
SELECT
    p.id_pelanggan,
    p.nama_pelanggan,
    COALESCE(SUM(dp.jumlah * dp.harga_satuan), 0) AS kalkulasi_total_belanja
FROM pelanggan p
LEFT JOIN pesanan ps ON p.id_pelanggan = ps.id_pelanggan
LEFT JOIN detail_pesanan dp ON ps.id_pesanan = dp.id_pesanan
GROUP BY p.id_pelanggan, p.nama_pelanggan;

-- ===== TAHAP 2: PENERAPAN DENORMALISASI =====
-- A. Menambah atribut turunan
ALTER TABLE pelanggan
ADD COLUMN total_belanja DECIMAL(15,2) DEFAULT 0;

-- B. Mengisi kolom dari hasil perhitungan Tahap 1 (2 baris berubah)
UPDATE pelanggan
SET total_belanja = (
    SELECT COALESCE(SUM(dp.jumlah * dp.harga_satuan), 0)
    FROM pesanan ps
    JOIN detail_pesanan dp ON ps.id_pesanan = dp.id_pesanan
    WHERE ps.id_pelanggan = pelanggan.id_pelanggan
);

-- ===== TAHAP 3: PEMBUKTIAN (tanpa JOIN dan agregasi) =====
SELECT id_pelanggan, nama_pelanggan, total_belanja
FROM pelanggan;

-- ===== PENGUJIAN LANJUTAN 1: DATA BESAR =====
-- 10.000 pelanggan, 50.000 pesanan, 100.000 detail pesanan.
-- Pelanggan baru ini masih total_belanja = 0 (belum disinkronkan).
CREATE TABLE digit (x INT);
INSERT INTO digit VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

CREATE TABLE angka (n INT PRIMARY KEY);
INSERT INTO angka (n)
SELECT a.x + b.x*10 + c.x*100 + d.x*1000 + e.x*10000
FROM digit a, digit b, digit c, digit d, digit e;

INSERT INTO pelanggan (id_pelanggan, nama_pelanggan)
SELECT 1000 + n, CONCAT('Pelanggan ', n) FROM angka WHERE n < 10000;

INSERT INTO pesanan (id_pesanan, id_pelanggan, tanggal)
SELECT 10000 + n, 1000 + (n % 10000), DATE_ADD('2026-01-01', INTERVAL (n % 300) DAY)
FROM angka WHERE n < 50000;

INSERT INTO detail_pesanan (id_detail, id_pesanan, jumlah, harga_satuan)
SELECT 1000 + n, 10000 + (n % 50000), 1 + (n % 5), 10000 + (n % 20) * 5000
FROM angka;

DROP TABLE digit;
DROP TABLE angka;

-- ===== PENGUJIAN LANJUTAN 2: DATA BARU MASUK (sebelum ada trigger) =====
-- Budi seharusnya menjadi 325000, tetapi total_belanja masih 250000.
INSERT INTO detail_pesanan (id_detail, id_pesanan, jumlah, harga_satuan)
VALUES (4, 101, 1, 75000);

-- ===== PENGUJIAN LANJUTAN 3: TRIGGER (hanya untuk INSERT) =====
CREATE TRIGGER trg_detail_after_insert
AFTER INSERT ON detail_pesanan
FOR EACH ROW
UPDATE pelanggan
SET total_belanja = total_belanja + (NEW.jumlah * NEW.harga_satuan)
WHERE id_pelanggan = (SELECT id_pelanggan FROM pesanan WHERE id_pesanan = NEW.id_pesanan);

-- Tes trigger: Siti naik dari 100000 menjadi 110000 tanpa UPDATE manual
INSERT INTO detail_pesanan (id_detail, id_pesanan, jumlah, harga_satuan)
VALUES (5, 102, 1, 10000);

SELECT id_pelanggan, nama_pelanggan, total_belanja
FROM pelanggan
WHERE id_pelanggan = 2;

-- ===== PENGUJIAN LANJUTAN 4: CEK KONSISTENSI (hasil: 10001 baris tidak cocok) =====
-- Budi (250000 vs 325000) dan 10.000 pelanggan dari data besar (0 vs nilai sebenarnya).
SELECT p.id_pelanggan,
       p.total_belanja AS tersimpan,
       COALESCE(h.total, 0) AS seharusnya
FROM pelanggan p
LEFT JOIN (
    SELECT ps.id_pelanggan, SUM(dp.jumlah * dp.harga_satuan) AS total
    FROM pesanan ps
    JOIN detail_pesanan dp ON ps.id_pesanan = dp.id_pesanan
    GROUP BY ps.id_pelanggan
) h ON h.id_pelanggan = p.id_pelanggan
WHERE p.total_belanja <> COALESCE(h.total, 0);

-- ===== PENGUJIAN LANJUTAN 5: SINKRONISASI ULANG (10001 baris berubah) =====
UPDATE pelanggan
SET total_belanja = (
    SELECT COALESCE(SUM(dp.jumlah * dp.harga_satuan), 0)
    FROM pesanan ps
    JOIN detail_pesanan dp ON ps.id_pesanan = dp.id_pesanan
    WHERE ps.id_pelanggan = pelanggan.id_pelanggan
);

-- ===== PENGUJIAN LANJUTAN 6: CEK ULANG (hasil: 0 baris = semua sinkron) =====
SELECT p.id_pelanggan,
       p.total_belanja AS tersimpan,
       COALESCE(h.total, 0) AS seharusnya
FROM pelanggan p
LEFT JOIN (
    SELECT ps.id_pelanggan, SUM(dp.jumlah * dp.harga_satuan) AS total
    FROM pesanan ps
    JOIN detail_pesanan dp ON ps.id_pesanan = dp.id_pesanan
    GROUP BY ps.id_pelanggan
) h ON h.id_pelanggan = p.id_pelanggan
WHERE p.total_belanja <> COALESCE(h.total, 0);

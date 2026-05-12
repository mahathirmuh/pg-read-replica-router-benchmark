# 🚀 Optimasi Query Routing pada Arsitektur Read Replica PostgreSQL

> **TOPIK 2C** — Mini Project Mata Kuliah Komputasi Berbasis Jaringan (KBJ)  
> Membandingkan 5 strategi query routing pada arsitektur PostgreSQL dengan 1 primary + 3 read replica heterogen.

---

## 📋 Daftar Isi

- [Deskripsi Proyek](#-deskripsi-proyek)
- [Arsitektur Sistem](#-arsitektur-sistem)
- [Strategi Routing](#-strategi-routing)
- [Struktur Direktori](#-struktur-direktori)
- [Prasyarat](#-prasyarat)
- [Instalasi & Setup](#-instalasi--setup)
- [Menjalankan Benchmark](#-menjalankan-benchmark)
- [Analisis & Visualisasi](#-analisis--visualisasi)
- [Skenario Eksperimen](#-skenario-eksperimen)
- [Metrik yang Diukur](#-metrik-yang-diukur)
- [Uji Statistik](#-uji-statistik)
- [Teknologi](#-teknologi)
- [Hasil Benchmark](#-hasil-benchmark)
- [Troubleshooting](#-troubleshooting)
- [Author](#-author)

---

## 📖 Deskripsi Proyek

Proyek ini mengimplementasikan **Custom Query Router Proxy** dalam Python yang secara otomatis mengarahkan query ke server PostgreSQL yang tepat:

- **Write queries** (INSERT, UPDATE, DELETE) → selalu dikirim ke **Primary**
- **Read queries** (SELECT) → diarahkan ke salah satu **Replica** berdasarkan strategi routing yang dipilih

Tujuan utama adalah membandingkan performa 5 strategi routing yang berbeda melalui benchmark yang rigorous, dengan variasi kompleksitas query dan rasio read/write.

---

## 🏗 Arsitektur Sistem

```
                    ┌──────────────────────────────────┐
                    │        Query Router Proxy         │
                    │   (Python asyncio + asyncpg)      │
                    │                                    │
                    │  ┌────────────┐ ┌──────────────┐  │
  Client ──────────►│  │  Query     │ │  Routing     │  │
  (50 concurrent)   │  │ Classifier │ │  Strategy    │  │
                    │  │ R/W split  │ │  (pluggable) │  │
                    │  └─────┬──────┘ └──────┬───────┘  │
                    │        │               │           │
                    │  ┌─────┴───────────────┴───────┐  │
                    │  │     Health Checker           │  │
                    │  │     (EMA α=0.3, 5s interval) │  │
                    │  └─────────────────────────────┘  │
                    └────────────┬───────────────────────┘
                                 │
              ┌──────────────────┼──────────────────────┐
              │                  │                       │
              ▼                  ▼                       ▼
    ┌─────────────────┐ ┌───────────────┐ ┌──────────────────┐
    │  pg_primary      │ │  pg_replica1  │ │  pg_replica2     │
    │  (READ + WRITE)  │ │  (READ only)  │ │  (READ only)     │
    │  2 CPU, 512 MB   │ │  2 CPU, 384MB │ │  1 CPU, 384MB    │
    │  Port: 5439      │ │  Port: 5440   │ │  Port: 5441      │
    └─────────────────┘ └───────────────┘ └──────────────────┘
                                                     │
                                          ┌──────────────────┐
                                          │  pg_replica3     │
                                          │  (READ only)     │
                                          │  0.5 CPU, 384MB  │
                                          │  Port: 5442      │
                                          └──────────────────┘
```

**Replikasi**: Asynchronous Streaming Replication (PostgreSQL 16)  
**Data**: 500.000 rows (tabel `orders`, `customers`, `products`)  
**Connection Pool**: 20 koneksi per backend

---

## 🔀 Strategi Routing

| # | Strategi | Key | Deskripsi |
|---|----------|-----|-----------|
| 1 | **Round-Robin** | `round_robin` | Distribusi query secara bergiliran ke semua replica yang sehat |
| 2 | **Load-Based** | `load_based` | Routing ke replica dengan penggunaan CPU terendah |
| 3 | **Latency-Based** | `latency_based` | Routing ke replica dengan latensi EMA terendah |
| 4 | **Weighted Round-Robin** | `weighted_rr` | Round-robin berbobot proporsional terhadap kapasitas CPU (4:2:1) |
| 5 | **Least-Connections** | `least_conn` | Routing ke replica dengan koneksi aktif paling sedikit |

Semua strategi diimplementasikan secara **pluggable** menggunakan Abstract Base Class dan strategy registry pattern.

---

## 📁 Struktur Direktori

```
KBJFP/
├── docker-compose.yml          # Konfigurasi cluster PostgreSQL (1 primary + 3 replica)
├── requirements.txt            # Dependency Python
├── test_router.py              # Smoke test untuk query router
├── verify_cluster.py           # Verifikasi koneksi cluster
│
├── docker/                     # Konfigurasi Docker
│   ├── primary/                # Setup primary (postgresql.conf, pg_hba.conf, init.sql)
│   └── replica/                # Setup replica (entrypoint.sh)
│
├── router/                     # 🔧 Core Query Router Module
│   ├── __init__.py
│   ├── query_router.py         # Main router proxy — klasifikasi & routing query
│   ├── strategies.py           # 5 strategi routing (pluggable)
│   ├── health_checker.py       # Background health check (EMA latency, CPU, koneksi)
│   └── metrics.py              # Kolektor metrik dan agregasi statistik
│
├── benchmark/                  # 📊 Benchmark Engine
│   ├── __init__.py
│   ├── queries.py              # Template query (simple, medium, complex)
│   ├── workload.py             # Profil workload (read-heavy 95:5, balanced 70:30)
│   ├── runner.py               # Eksekutor benchmark (50 concurrent clients, warm-up)
│   └── run_all.py              # Orkestrator: iterasi semua kombinasi eksperimen
│
├── analysis/                   # 📈 Analisis & Visualisasi
│   ├── __init__.py
│   ├── stats_analysis.py       # Kruskal-Wallis, Dunn's post-hoc, Two-way ANOVA, Gini
│   ├── visualize.py            # Bar chart, scatter plot, load distribution
│   ├── report_tables.py        # Tabel ringkasan untuk laporan
│   └── generate_mock_data.py   # Generator data mock untuk testing
│
├── results/                    # 📂 Output Benchmark (JSON per run + summary.csv)
│   ├── *.json                  # Hasil per kombinasi (strategy__complexity__workload__repN)
│   └── summary.csv             # Ringkasan semua run
│
└── analysis_output/            # 📉 Output Analisis
    ├── anova.txt               # Hasil Two-way ANOVA
    ├── kruskal_dunn.txt         # Hasil Kruskal-Wallis + Dunn's post-hoc
    ├── gini_fairness.csv       # Koefisien Gini per strategi
    ├── bar_*.png               # Bar chart perbandingan metrik
    ├── scatter_tradeoff_*.png  # Scatter plot latency vs throughput
    ├── dist_*.png              # Distribusi load per replica
    ├── heatmap_latency.png     # Heatmap latensi
    ├── radar_chart.png         # Radar chart multidimensi
    └── box_plots.png           # Box plot perbandingan
```

---

## ⚙ Prasyarat

- **Docker** & **Docker Compose** (untuk menjalankan cluster PostgreSQL)
- **Python** 3.11+
- ~2 GB RAM tersedia (untuk 4 container PostgreSQL)

---

## 🛠 Instalasi & Setup

### 1. Clone Repository

```bash
git clone https://github.com/mahathirmuh/routing-query.git
cd routing-query
```

### 2. Install Dependency Python

```bash
pip install -r requirements.txt
```

**Dependency utama:**
| Package | Fungsi |
|---------|--------|
| `asyncpg` | Async PostgreSQL driver |
| `psycopg2-binary` | Sync PostgreSQL driver (utilities) |
| `numpy`, `scipy`, `pandas` | Komputasi data & analisis |
| `matplotlib`, `seaborn` | Visualisasi |
| `scikit-posthocs` | Dunn's post-hoc test |
| `tqdm` | Progress bar |

### 3. Setup Cluster PostgreSQL

```bash
# Jalankan cluster (1 primary + 3 replica)
docker compose up -d

# Verifikasi semua container berjalan
docker compose ps

# Verifikasi koneksi & replikasi
python verify_cluster.py
```

### 4. Smoke Test Router

```bash
# Test semua 5 strategi routing
python test_router.py
```

Output yang diharapkan:
```
  [ALL PASS] All 5 strategies working correctly!
```

---

## 🏃 Menjalankan Benchmark

### Full Benchmark (30 kombinasi × 5 repetisi = 150 run)

```bash
# Full benchmark (~25 jam)
python -m benchmark.run_all

# Custom parameter
python -m benchmark.run_all --duration 300 --reps 3 --concurrency 30
```

### Quick Smoke Test

```bash
# Mode cepat: 60s per run, 1 repetisi, 10 concurrency
python -m benchmark.run_all --quick
```

### Benchmark Selektif

```bash
# Hanya strategi tertentu
python -m benchmark.run_all --strategies round_robin load_based

# Hanya workload read_heavy
python -m benchmark.run_all --workloads read_heavy

# Hanya kompleksitas simple
python -m benchmark.run_all --complexities simple

# Re-run semua (tanpa skip yang sudah selesai)
python -m benchmark.run_all --no-resume
```

### Parameter CLI

| Parameter | Default | Deskripsi |
|-----------|---------|-----------|
| `--duration` | 600 (10 menit) | Durasi per run dalam detik |
| `--concurrency` | 50 | Jumlah concurrent client |
| `--warmup` | 1000 | Jumlah query warm-up |
| `--reps` | 5 | Jumlah repetisi per kombinasi |
| `--strategies` | semua | Strategi yang diuji |
| `--complexities` | semua | Level kompleksitas query |
| `--workloads` | semua | Profil workload |
| `--no-resume` | false | Re-run semua (jangan skip yang selesai) |
| `--quick` | false | Mode cepat (60s, 1 rep, 10 concurrency) |

---

## 📊 Analisis & Visualisasi

### Jalankan Analisis Statistik

```bash
python -m analysis.stats_analysis
```

Output: `analysis_output/kruskal_dunn.txt`, `anova.txt`, `gini_fairness.csv`

### Generate Visualisasi

```bash
python -m analysis.visualize
```

Output: Chart PNG di folder `analysis_output/`

### Generate Tabel Laporan

```bash
python -m analysis.report_tables
```

---

## 📅 Fase Pengerjaan

Proyek ini dikembangkan dalam **4 fase** sesuai timeline yang ditetapkan:

### Fase 1 — Setup Infrastruktur Cluster PostgreSQL ✅
> **Pekan 1** | Setup PG cluster + replication + data

| Deliverable | Deskripsi |
|-------------|-----------|
| `docker-compose.yml` | Cluster 4 node PostgreSQL 16 (1 primary + 3 replica heterogen) |
| `docker/primary/postgresql.conf` | Konfigurasi WAL + streaming replication |
| `docker/primary/pg_hba.conf` | Aturan autentikasi untuk replikasi dan client |
| `docker/primary/init.sql` | Schema database `benchmark` + seed 500K rows (`orders`, `customers`, `products`) |
| `docker/primary/setup_replication.sh` | Script pembuatan replication slot otomatis |
| `docker/replica/entrypoint.sh` | Entrypoint replica: `pg_basebackup` + standby config (dengan `gosu` untuk keamanan) |
| `verify_cluster.py` | Script verifikasi: konektivitas, replikasi, konsistensi data, read-only check |

**Keputusan desain:**
- Replica heterogen dengan resource limit berbeda (2.0 / 1.0 / 0.5 CPU) untuk simulasi lingkungan nyata
- Seed data menggunakan `setseed(0.42)` agar dataset tetap konsisten di setiap pengujian
- Port primary di-remap ke `5439` untuk menghindari konflik dengan PostgreSQL lokal

---

### Fase 2 — Custom Query Router Proxy ✅
> **Pekan 2** | Implementasi Router + 5 strategi routing

| Deliverable | Deskripsi |
|-------------|-----------|
| `router/strategies.py` | 5 strategi routing pluggable (ABC + strategy registry pattern) |
| `router/health_checker.py` | Background health check async (EMA α=0.3, interval 5s) |
| `router/metrics.py` | Kolektor 7 metrik benchmark + export JSON/CSV |
| `router/query_router.py` | Main proxy: klasifikasi R/W via regex, connection pooling, routing |
| `test_router.py` | Smoke test: validasi semua 5 strategi (simple/medium/complex read + write) |

**Keputusan desain:**
- Weighted Round-Robin menggunakan algoritma Nginx-style smooth weighting untuk distribusi merata
- EMA latency di-update baik oleh health checker (background) maupun per-query execution (real-time)
- Query classifier menggunakan regex pattern matching (`SELECT`, `SHOW`, `EXPLAIN`, `WITH...SELECT`)

---

### Fase 3 — Benchmark Runner + Integrasi ✅
> **Pekan 3** | Engine benchmark + orkestrator eksperimen

| Deliverable | Deskripsi |
|-------------|-----------|
| `benchmark/queries.py` | Template query 3 level kompleksitas (PK lookup → JOIN 2 → JOIN 3 + aggregasi) |
| `benchmark/workload.py` | Profil workload: Read-Heavy (95:5) dan Balanced (70:30) |
| `benchmark/runner.py` | Engine: 50 concurrent clients, warm-up 1000 queries, durasi 10 menit |
| `benchmark/run_all.py` | Orkestrator: 30 kombinasi × 5 repetisi, auto-resume, CLI args, `--quick` mode |

**Keputusan desain:**
- Setiap worker menggunakan seed unik (`base_seed + worker_id`) untuk menghindari query identik antar client
- Fitur **auto-resume**: run yang sudah selesai disimpan sebagai `.json` dan di-skip saat re-run
- Prioritas eksekusi: Read-Heavy workload dijalankan terlebih dahulu

---

### Fase 4 — Analisis Statistik + Visualisasi ✅
> **Pekan 4** | Eksekusi benchmark + analisis + report

| Deliverable | Deskripsi |
|-------------|-----------|
| `analysis/stats_analysis.py` | Kruskal-Wallis H-test, Dunn's post-hoc (Holm), Two-way ANOVA, Gini coefficient |
| `analysis/visualize.py` | Bar chart, scatter trade-off, stacked bar distribusi load |
| `analysis/report_tables.py` | Generator tabel `Mean ± Std` untuk laporan akademis |

**Keputusan desain:**
- File `statistics.py` di-rename menjadi `stats_analysis.py` untuk menghindari konflik dengan modul bawaan Python
- Dunn's post-hoc menggunakan koreksi Holm untuk multiple comparison
- Visualisasi menggunakan DPI 300 untuk kualitas cetak/publikasi

---

## 🧪 Skenario Eksperimen

### Variabel Independen

| Variabel | Level |
|----------|-------|
| **Routing Strategy** | Round-Robin, Load-Based, Latency-Based, Weighted-RR, Least-Conn |
| **Query Complexity** | Simple (PK lookup), Medium (JOIN 2 tabel), Complex (JOIN 3 + aggregasi) |
| **Read/Write Ratio** | Read-Heavy (95:5), Balanced (70:30) |

### Variabel Tetap

| Parameter | Nilai |
|-----------|-------|
| PostgreSQL Version | 16.x |
| Jumlah Replica | 3 (heterogen: 2/1/0.5 CPU) |
| Dataset | 500.000 rows |
| Replikasi | Asynchronous Streaming |
| Connection Pool | 20 koneksi per backend |
| Health Check Interval | 5 detik |
| EMA Alpha | 0.3 |
| Concurrent Clients | 50 |
| Random Seed | Fixed (reproducible) |
| Warm-up | 1.000 queries |

### Total Kombinasi

```
5 strategi × 3 complexity × 2 ratio = 30 kombinasi
30 kombinasi × 5 repetisi = 150 total run
```

---

## 📐 Metrik yang Diukur

| # | Metrik | Satuan | Deskripsi |
|---|--------|--------|-----------|
| 1 | **Read Avg Latency** | ms | Rata-rata latensi read query |
| 2 | **Read P95 Latency** | ms | Persentil ke-95 latensi read |
| 3 | **Overall Throughput** | qps | Query berhasil per detik |
| 4 | **Load Distribution CV** | float | Coefficient of Variation distribusi query antar replica |
| 5 | **Per-Replica CPU** | % | Rata-rata penggunaan CPU per replica |
| 6 | **Staleness Rate** | % | Persentase read yang mendapat data basi |
| 7 | **Router Overhead** | ms | Waktu tambahan untuk keputusan routing |

---

## 📈 Uji Statistik

| Analisis | Fungsi |
|----------|--------|
| **Kruskal-Wallis H-test** | Perbandingan non-parametrik 5 strategi per kombinasi |
| **Dunn's Post-Hoc** | Identifikasi pasangan strategi yang berbeda signifikan (α = 0.05) |
| **Two-way ANOVA** | Interaksi Strategy × Complexity (parametrik) |
| **Gini Coefficient** | Fairness distribusi query ke replica |

### Visualisasi yang Dihasilkan

| Jenis | Deskripsi |
|-------|-----------|
| **Bar Chart** | Perbandingan latency, throughput, dan load CV |
| **Scatter Plot** | Trade-off latency vs throughput (ideal: kanan bawah) |
| **Stacked Bar** | Distribusi query per replica per strategi |
| **Heatmap** | Latensi — strategy (baris) × complexity×ratio (kolom) |
| **Radar Chart** | Perbandingan multidimensi per strategi |
| **Box Plot** | Distribusi metrik antar repetisi |

---

## 🧰 Teknologi

| Komponen | Teknologi |
|----------|-----------|
| **Database** | PostgreSQL 16 |
| **Containerization** | Docker & Docker Compose |
| **Bahasa** | Python 3.11+ |
| **Async I/O** | asyncio + asyncpg |
| **Data Analysis** | pandas, numpy, scipy |
| **Visualization** | matplotlib, seaborn |
| **Statistical Tests** | scipy.stats, scikit-posthocs, statsmodels |

---

## 📊 Hasil Benchmark

> [!NOTE]
> Angka di bawah ini adalah agregat dari **150 run aktual** (5 strategi × 3 complexity × 2 ratio × 5 repetisi) yang tercatat di [`results/summary.csv`](results/summary.csv). Visualisasi grafis (`.png`) tersedia di folder [`analysis_output/`](analysis_output/) dan siap di-copy ke laporan.

Tabel diurutkan berdasarkan latency Complex (ascending). Pemenang per workload di-bold.

### Read-Heavy Workload (95:5)

| Strategi | Simple (ms) | Medium (ms) | Complex (ms) | Simple QPS | Medium QPS | Complex QPS |
|----------|:-----------:|:-----------:|:------------:|:----------:|:----------:|:-----------:|
| **Weighted-RR** | **13.57 ± 0.29** | **39.05 ± 2.85** | **2970.56 ± 45.80** | **3425** | **1310** | **18** |
| Latency-Based | 13.87 ± 0.35 | 47.76 ± 4.20 | 4072.37 ± 60.80 | 3395 | 1084 | 13 |
| Load-Based | 13.74 ± 0.42 | 40.66 ± 4.37 | 4309.30 ± 90.98 | 3473 | 1270 | 12 |
| Least-Conn | 12.80 ± 0.16 | 88.42 ± 2.14 | 4675.00 ± 2517.13 | 3612 | 590 | 13 |
| Round-Robin | 13.70 ± 1.17 | 57.81 ± 2.31 | 5007.41 ± 139.89 | 3455 | 898 | 10 |

### Balanced Workload (70:30)

| Strategi | Simple (ms) | Medium (ms) | Complex (ms) | Simple QPS | Medium QPS | Complex QPS |
|----------|:-----------:|:-----------:|:------------:|:----------:|:----------:|:-----------:|
| **Weighted-RR** | **3.61 ± 0.30** | **273.56 ± 5.65** | **9052.21 ± 464.12** | 1528 | **250** | **8** |
| Least-Conn | 3.59 ± 0.15 | 478.72 ± 4.22 | 9301.11 ± 171.64 | 1505 | 146 | 8 |
| Load-Based | 3.39 ± 0.05 | 404.35 ± 17.24 | 11780.91 ± 574.30 | 1755 | 172 | 6 |
| Latency-Based | 3.79 ± 0.24 | 387.17 ± 5.88 | 14385.47 ± 510.13 | 1665 | 180 | 5 |
| Round-Robin | 3.41 ± 0.56 | 515.28 ± 20.46 | 16625.94 ± 531.72 | **1956** | 136 | 4 |

### Fairness (Load CV — semakin rendah semakin merata)

| Strategi | Read-Heavy | Balanced |
|----------|:----------:|:--------:|
| **Round-Robin** | **0.463** | **0.115** |
| Weighted-RR | 0.747 | 0.447 |
| Least-Conn | 0.934 | 0.570 |
| Latency-Based | 1.003 | 0.506 |
| Load-Based | 1.558 | 1.055 |

### Temuan Utama

1. **Weighted Round-Robin** adalah pemenang konsisten pada workload **medium** dan **complex** di kedua rasio read/write — masuk akal karena bobot statis 4:2:1 secara matematis cocok dengan rasio kapasitas CPU replica (2:1:0.5).
2. **Pada simple workload (PK lookup), perbedaan antar strategi praktis tidak signifikan** (semua 3.4–3.8 ms balanced, 12.8–13.9 ms read-heavy) — overhead routing > selisih kerja replica.
3. **Round-Robin memberikan distribusi paling merata** (Load CV terendah: 0.115 balanced, 0.463 read-heavy) tetapi menjadi yang terlambat pada query medium/complex karena mengabaikan heterogenitas kapasitas.
4. **Latency-Based dan Load-Based underperform** pada complex workload — keputusan reaktif berbasis EMA tidak konvergen cepat ketika query memakan ribuan milidetik dan latency antar replica berbeda hingga 5×.
5. **Kruskal-Wallis** menunjukkan perbedaan signifikan antar strategi pada semua kombinasi (p < 0.05); **Two-way ANOVA** mengkonfirmasi interaksi signifikan Strategy × Complexity (p < 0.001) dengan kompleksitas query memberi efek dominan (F = 4205.66 untuk read-heavy).
6. **Rekomendasi praktis**: gunakan **Weighted-RR** untuk cluster heterogen dengan workload non-trivial; gunakan **Round-Robin** jika fairness distribusi adalah prioritas utama (mis. untuk audit/billing per-replica).

---

## ❓ Troubleshooting

### Docker Container Tidak Bisa Start

```bash
# Cek status container
docker compose ps

# Lihat log container yang bermasalah
docker compose logs pg_primary
docker compose logs pg_replica1

# Restart seluruh cluster
docker compose down -v
docker compose up -d
```

### Replica Tidak Bisa Konek ke Primary

- Pastikan `pg_hba.conf` mengizinkan koneksi replikasi
- Pastikan `postgresql.conf` pada primary sudah mengatur `wal_level = replica`
- Periksa network Docker: semua container harus dalam `pg_network` yang sama

```bash
# Verifikasi replikasi dari primary
docker exec pg_primary psql -U postgres -d benchmark \
  -c "SELECT * FROM pg_stat_replication;"
```

### Benchmark Gagal dengan Connection Error

```bash
# Pastikan pool size tidak melebihi max_connections
docker exec pg_primary psql -U postgres -c "SHOW max_connections;"

# Periksa koneksi aktif
docker exec pg_primary psql -U postgres \
  -c "SELECT count(*) FROM pg_stat_activity;"
```

### Port Konflik

Default port mapping di `docker-compose.yml`:

| Container | Port Host | Port Container |
|-----------|:---------:|:--------------:|
| pg_primary | 5439 | 5432 |
| pg_replica1 | 5440 | 5432 |
| pg_replica2 | 5441 | 5432 |
| pg_replica3 | 5442 | 5432 |

Jika port sudah dipakai, ubah di `docker-compose.yml` dan sesuaikan konfigurasi di `router/query_router.py`.

### Benchmark Berjalan Lambat

- Pastikan Docker memiliki cukup resource (CPU & RAM)
- Gunakan `--quick` untuk smoke test sebelum full benchmark
- Gunakan `--duration 60 --reps 1` untuk testing cepat
- Benchmark mendukung **resume** — jika terputus, jalankan ulang dan run yang sudah selesai akan di-skip otomatis

### Module Import Error

```bash
# Pastikan menjalankan dari root directory proyek
# Jalankan dengan -m flag
python -m benchmark.run_all    # ✅ Benar
python benchmark/run_all.py     # ❌ Bisa error import
```

---

## 👤 Author

- **Mahathir Muhammad**
- **Obi Kastanya**
- **Ananta Dwi Prayoga Alwy**
- Program Studi S2 — Teknik Informatika 
- Mata Kuliah : Komputasi Berbasis Jaringan
- Dosen Pengampu : Bagus Jati Santoso, S.Kom., Ph.D.
---

## Lisensi

Proyek ini dikembangkan untuk keperluan akademis pada mata kuliah **Komputasi Berbasis Jaringan — S2 Tesis**.

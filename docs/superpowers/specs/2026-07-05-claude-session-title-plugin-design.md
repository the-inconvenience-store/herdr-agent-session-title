# Tasarım: claude-session-title herdr plugin'i

Tarih: 2026-07-05
Durum: Onaylandı (brainstorming oturumunda bölüm bölüm onaylandı)
Depo: `bcihanc/herdr-claude-session-title` (herdr çekirdeğinden bağımsız, ayrı proje)

## Amaç

Claude Code'da `/rename` ile verilen oturum adının (ve ad verilmemişse
Claude Code'un otomatik ürettiği özet başlığın) herdr'daki ilgili pane'in
**metadata title** alanına otomatik yansıması. Pane'in sidebar etiketi
değişmez; oturum adı gezgin/detay görünümündeki title alanında görünür.

## Fizibilite bulguları (doğrulanmış)

- `/rename`, oturumun transcript dosyasına (`~/.claude/projects/<slug>/<session-id>.jsonl`)
  kalıcı bir satır yazar: `{"type":"custom-title","customTitle":"...","sessionId":"..."}`.
  Aynı anda `{"type":"agent-name","agentName":"..."}` satırı da yazılır.
  (Yerel makinede Claude Code 2.1.201 ile doğrulandı.)
- Otomatik özet başlık, transcript ile aynı dizindeki `sessions-index.json`
  dosyasında `entries[].summary` alanında durur (`sessionId` ile eşlenir).
  Bu indeks gecikmeli/eksik olabilir; en-iyi-çaba (best-effort) kaynağıdır.
- Claude Code'da rename'e özel bir hook olayı yoktur; hook girdileri oturum
  adını içermez. Ancak hook girdisi `transcript_path` ve `session_id` taşır —
  ad, transcript'ten okunabilir.
- Claude Code terminal başlığı (OSC 0/2) yaymaz; o yol kapalıdır.
- Herdr tarafında hazır altyapı: `pane.report_metadata` soket metodu
  (`herdr pane report-metadata ... --title` CLI karşılığı) title'ı kabul eder
  ve arayüzde gösterir. Birden çok kaynak title bildirirse **en son bildirilen
  kazanır** (`newest_metadata_title`). Herdr'ın yerleşik Claude entegrasyonu
  title bildirmediği için çakışma yoktur.
- Hook betiği pane içinde çalıştığından `HERDR_ENV=1`, `HERDR_PANE_ID` ve
  `HERDR_SOCKET_PATH` ortam değişkenlerini otomatik devralır.

## Onaylanan kararlar

| Karar | Seçim |
|---|---|
| Hedef alan | Pane metadata title (sidebar etiketi değil) |
| Kapsam | `/rename` adı öncelikli; yoksa otomatik özet başlık |
| Dağıtım | Bağımsız herdr plugin'i (`herdr plugin install bcihanc/herdr-claude-session-title`) |
| Gecikme | Sonraki etkileşimde güncellenme yeterli (anlık takip yok, arka plan süreci yok) |
| Platformlar | linux + macos (Windows ilk sürümde kapsam dışı) |
| Herdr çekirdeği | Sıfır değişiklik; yalnızca mevcut kararlı API'ler kullanılır |

## Mimari ve veri akışı

```
Claude Code (pane içinde)
   │  hook olayı: SessionStart / UserPromptSubmit / Stop
   ▼
hook.sh (~/.claude/hooks/herdr-claude-session-title.sh)
   │  1. Hook girdisi (stdin JSON) → transcript_path, session_id
   │  2. Transcript'te SON "custom-title" satırı → customTitle
   │  3. Yoksa sessions-index.json → sessionId eşleşen entry → summary
   │  4. O da yoksa sessizce çık (mevcut title'a dokunma)
   ▼
python3 ile HERDR_SOCKET_PATH soketine tek JSON isteği:
   pane.report_metadata { pane_id, source: "plugin:claude-session-title",
                          agent: "claude", title, seq: time_ns }
   ▼
herdr → EffectivePresentation.title → gezgin/detay görünümünde görünür
```

Kilit noktalar:

- **Soketle doğrudan konuşma:** Hook çalışırken `herdr` binary'sinin PATH'te
  olma garantisi yok; `HERDR_SOCKET_PATH` her zaman hazır. Yerleşik
  entegrasyon betiği (`herdr-agent-state.sh`) ile aynı desen: python3 ile
  0,5 sn zaman aşımlı tek istek.
- **Güncelleme anları:** `SessionStart` (açılış/`--resume` sonrası ad hemen
  görünür), `UserPromptSubmit` (rename sonrası ilk mesajda güncellenir),
  `Stop` (her duruşta güncellenir).
- **seq:** Nanosaniye zaman damgası; eski bildirimin yeniyi ezmesini önler
  (herdr kaynak başına seq'i monoton bekler).

## Bileşenler

```
herdr-claude-session-title/
  herdr-plugin.toml        # manifest
  scripts/
    hook.sh                # Claude Code hook betiği (asıl iş)
    install.sh             # "install" aksiyonu
    uninstall.sh           # "uninstall" aksiyonu
    status.sh              # "status" aksiyonu (teşhis)
  tests/
    test-extract.sh        # ad çıkarma birim testleri
    test-socket.sh         # sahte soket sunucusuyla uçtan uca hook testi
    test-install.sh        # install/uninstall idempotentlik testleri
    fixtures/              # örnek transcript ve sessions-index dosyaları
  docs/superpowers/specs/  # bu tasarım dokümanı
  README.md                # kurulum + elle doğrulama adımları
```

- **Manifest:** `id = "bcihanc.claude-session-title"`, `platforms = ["linux", "macos"]`,
  `min_herdr_version = "0.7.0"` (plugin API v1'i taşıyan sürüm; implementasyonda güncel herdr sürümüne göre doğrulanacak). Üç `[[actions]]`:
  `install`, `uninstall`, `status`.
- **hook.sh:** Savunmacı koruma sırası: `HERDR_ENV=1` → `HERDR_PANE_ID` →
  `HERDR_SOCKET_PATH` → `python3` mevcut; biri eksikse `exit 0`. Alt-ajan
  (subagent) hook olayları atlanır (`agent_id` alanı doluysa). Ad çıkarma
  mantığı ayrı, source-edilebilir bir fonksiyonda durur (test edilebilirlik).
- **install.sh:** (a) `hook.sh`'ı sabit yola kopyalar:
  `~/.claude/hooks/herdr-claude-session-title.sh` — plugin yeniden
  kurulduğunda plugin kök dizini değişse bile Claude ayarlarındaki kayıt
  kırılmaz. (b) `~/.claude/settings.json`'a üç hook kaydını (SessionStart,
  UserPromptSubmit, Stop; `timeout: 10`) python3 ile idempotent ekler;
  başka araçların hook kayıtlarına dokunmaz.
- **uninstall.sh:** Yalnızca kendi üç kaydını ve kopya betiği kaldırır.
- **status.sh:** Kayıt var mı, kopya güncel mi (checksum), soket erişilebilir
  mi — kısa teşhis çıktısı.

## Hata yönetimi

İlke: **hook asla Claude Code'u rahatsız etmez.**

- Her hata yolu `exit 0` (sessiz çıkış): transcript okunamadı, JSON bozuk,
  soket kapalı, herdr kapalı, index yok.
- Soket bağlantısı 0,5 sn zaman aşımlı; hook kaydında ayrıca `timeout: 10`.
- Büyük transcript'lerde tam dosya belleğe alınmaz; son `custom-title`
  satırı `grep` ile bulunur.
- Title temizliği: kontrol karakterleri ayıklanır, 120 karakterde kesilir.
- Herdr dışında (normal terminalde) `HERDR_ENV` yok → ilk korumada çıkış.
- `install.sh` settings.json'ı düzenlemeden önce yedek alır
  (`settings.json.bak-claude-session-title`); yazım geçici dosya + atomik
  taşıma ile yapılır.

## Test planı

1. **Birim (çevrimdışı):** `tests/test-extract.sh` — fixture'larla ad çıkarma:
   tek rename, çoklu rename (sonuncusu kazanır), yalnız otomatik özet,
   ikisi de yok, bozuk JSON satırı. Herdr/Claude gerekmez.
2. **Soket sahtesi:** Geçici Unix soketi dinleyen mini python sunucu;
   hook.sh sahte ortamla çalıştırılır; gönderilen isteğin
   `pane.report_metadata` şekli ve title içeriği doğrulanır.
3. **Kurulum idempotentliği:** Geçici settings.json üzerinde
   install → install → uninstall; çift kayıt yok, yabancı kayıtlar korunur.
4. **Uçtan uca elle doğrulama (README):** herdr pane'inde Claude Code aç →
   `/rename deneme-adi` → bir mesaj gönder → herdr gezgininde pane
   detayında adı gör. Sorun ayıklama: `herdr plugin log list`.

## Kapsam dışı (bilinçli)

- Windows desteği (PowerShell hook betiği) — gelecek sürüm adayı.
- Anlık güncelleme (transcript dosyası izleyici/daemon) — gecikme kararıyla elendi.
- Sidebar pane etiketini değiştirmek (`pane rename`) — kullanıcı tercihiyle elendi.
- Herdr çekirdeğine/yerleşik entegrasyona upstream katkı — ayrı, isteğe bağlı
  bir gelecek adım; bu plugin o zamana kadar köprü görevi görür.

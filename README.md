<div align="center">

# 🔄 Termux Auto Updater

### *Безопасное обновление пакетов, инструментов и CLI-агентов в Android Termux по стандартам termux-fix-path*

[![Termux](https://img.shields.io/badge/Termux-Android-000000?style=for-the-badge&logo=termux&logoColor=white)](https://termux.dev/)
[![Bash](https://img.shields.io/badge/Bash-Automation-2B35AF?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Termux Fix](https://img.shields.io/badge/Standard-termux--fix--path-4EAA25?style=for-the-badge)](https://github.com/Enigman-Termux-lab/lab-termux-fix)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)

<br/>

**Termux Auto Updater** — готовый скрипт и скилл для безопасной проверки и обновления программной среды в Termux на Android. В отличие от стандартных Linux-скриптов обновления, инструмент адаптирован под специфику Android/Bionic, предотвращает поломку путей shebang и защищает системные компоненты от конфликтов.

---

</div>

## 💡 Что делает скрипт обновления

Скрипт `scripts/update_all.sh` автоматизирует полный цикл обновления с многоуровневой защитой:

1. **Системные пакеты Termux (`pkg` / `apt`):**
   - Обновляет репозитории и установленные пакеты в неинтерактивном режиме с сохранением существующих пользовательских конфигов (`--force-confold`).
2. **Очистка теневых обёрток (`~/.local/bin/`):**
   - Проверяет наличие старых лаунчеров, перехватывающих нативные бинарники из `$PREFIX/bin`, и безопасно переносит их в `~/.local/state/backups/`.
3. **Глобальные NPM-пакеты и Codex CLI:**
   - Обновляет глобальные пакеты Node.js (включая `@mmmbuto/codex-cli-termux`).
   - Исключает пакет `@anthropic-ai/claude-code`, предотвращая повреждение изолированных инсталляций.
4. **Автоматический ремонт Shebang (`termux-fix-shebang`):**
   - Сканирует исполняемые скрипты в `$(npm prefix -g)/bin` и внутренних каталогах модулей, восстанавливая корректный Termux shebang (`#!/data/data/com.termux/files/usr/bin/...`).
   - Никогда не трогает бинарные файлы ELF.
5. **Python/pip и утилиты `uv`:**
   - Запрашивает отдельное подтверждение на обновление pip-пакетов, чтобы избежать конфликтов с системным менеджером `pkg`.
   - Обновляет изолированные инструменты через `uv tool upgrade --all`.
6. **Автономное ядро Antigravity CLI (`agy update`):**
   - Делегирует обновление встроенному механизму `agy`, проверяющему совместимость перед применением.
7. **Пост-проверка работоспособности (Post-flight verification):**
   - Тестирует запуск доверенных инструментов (`codex --version`, `agy --help`) и логирует все шаги в `/tmp/auto_update_*.log`.
8. **Кулдаун 7 дней:**
   - Предотвращает избыточные циклы обновления через проверку метки времени в `last_update.timestamp`.

---

## 🔗 Главный апстрим ядра: wallentx/antigravity-cli-termux

Главным портом автономного ИИ-ядра для Android Termux является официальный репозиторий:
👉 **[wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux)**

Официальный порт включает:
- **NDK Bionic Bootstrapper (`agy`):** нативный исполняемый файл для Android с автоматическим расчётом путей, сбросом конфликтующих переменных и контролем сетевого стека Go (`GODEBUG=netdns=cgo`);
- **Patched glibc Engine (`agy.va39`):** бинарник движка, оптимизированный под 39-битное адресное пространство виртуальной памяти (VA39) мобильных чипсетов, что исключает ошибки `MmapAligned() failed` и `SIGSEGV` в Google TCMalloc.

### Установка или переустановка апстрима:
```bash
curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash
```

---

## 🚀 Быстрый запуск

### 1. Клонирование репозитория
```bash
git clone https://github.com/Enigman-Termux-lab/termux-auto-updater.git ~/projects/lab-auto-updater
cd ~/projects/lab-auto-updater
```

### 2. Запуск проверки и обновления
```bash
./scripts/update_all.sh
```

При запуске скрипт покажет список всех доступных обновлений и запросит явное интерактивное подтверждение перед внесением изменений.

---

## 📄 Лицензия

Распространяется под лицензией [MIT](LICENSE). Разработано для открытой экосистемы **[Enigman-Termux-lab](https://github.com/Enigman-Termux-lab)**.

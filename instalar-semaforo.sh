#!/bin/bash
# =============================================================================
#  Semáforo Sonoro — transforma um Debian 13 num "quiosque":
#  liga -> entra sozinho -> abre o semáforo em ecrã inteiro.
#  O botão de ligar/desligar do computador encerra o sistema de forma segura.
#
#  Uso:  sudo bash instalar-semaforo.sh
#  (na mesma pasta: semaforo-sonoro-teste.html e servidor.py; se faltarem,
#   são descarregados do GitHub)
#
#  v2 (27/09/2026): funciona com ambiente gráfico instalado, ecrã inteiro garantido, IP no canto.
#  v3 (27/09/2026): servidor SSH e comando semaforo-hdmi.
#  v4 (29/09/2026): servidor local + definições pelo telemóvel (http://IP-do-PC, com PIN);
#                   atualização automática da página a partir do GitHub em cada arranque;
#                   passa as definições antigas do browser para o PC (uma vez).
#  v5 (01/10/2026): descarrega do GitHub pelo API (api.github.com), porque a rede da escola
#                   bloqueia raw.githubusercontent.com; o endereço antigo fica como alternativa.
#                   Desligar automaticamente às horas definidas na página (a conta semaforo só
#                   tem autorização para desligar o PC, nada mais).
# =============================================================================
set -euo pipefail

UTILIZADOR="semaforo"
GITHUB="https://raw.githubusercontent.com/helderlramos/semaforo-sonoro/main"
GITHUB_API="https://api.github.com/repos/helderlramos/semaforo-sonoro/contents"
PASTA_SCRIPT="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "Corre este script como administrador:  sudo bash instalar-semaforo.sh"; exit 1; }

# --- 1. Utilizador --------------------------------------------------------------
if ! id "$UTILIZADOR" >/dev/null 2>&1; then
  echo ">> A criar o utilizador $UTILIZADOR"
  adduser --disabled-password --gecos "Semaforo" "$UTILIZADOR"
fi
usermod -aG audio,video "$UTILIZADOR"
CASA="$(getent passwd "$UTILIZADOR" | cut -d: -f6)"
UID_U="$(id -u "$UTILIZADOR")"

# --- 2. Desligar o ecrã de entrada gráfico, se existir --------------------------
# (Xfce/GNOME/KDE ficam instalados, mas não arrancam; o semáforo usa o terminal 1)
for dm in lightdm gdm3 gdm sddm lxdm; do
  systemctl disable "$dm" >/dev/null 2>&1 || true
done
systemctl set-default multi-user.target >/dev/null 2>&1 || true

# --- 3. Pacotes -----------------------------------------------------------------
echo ">> A instalar pacotes (pode demorar alguns minutos)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  xserver-xorg-core xserver-xorg-video-all xserver-xorg-input-libinput \
  xinit x11-xserver-utils unclutter \
  chromium \
  pipewire pipewire-pulse wireplumber pipewire-alsa alsa-utils dbus-user-session pulseaudio-utils \
  openssh-server python3 curl iproute2 sudo \
  fonts-dejavu-core fonts-noto-color-emoji

# --- 4. Pastas, página e servidor ----------------------------------------------
install -d -o "$UTILIZADOR" -g "$UTILIZADOR" "$CASA/semaforo"
install -d -m 700 -o "$UTILIZADOR" -g "$UTILIZADOR" "$CASA/semaforo-dados"

obter() {   # obter <ficheiro> <destino> : usa a cópia da pasta do script ou descarrega do GitHub
  if [ -f "$PASTA_SCRIPT/$1" ]; then
    cp "$PASTA_SCRIPT/$1" "$2"
  else
    echo ">> $1 não está na pasta; a descarregar do GitHub..."
    curl -fsSL --max-time 60 -H "Accept: application/vnd.github.raw" "$GITHUB_API/$1?ref=main" -o "$2" \
      || curl -fsSL --max-time 60 "$GITHUB/$1" -o "$2"
  fi
}

TMP_PAGINA="$(mktemp)"
obter semaforo-sonoro-teste.html "$TMP_PAGINA"
grep -q 'SEMAFORO_PAGINA_OK' "$TMP_PAGINA" || { echo "A página não está completa (falta a marca final)."; exit 1; }
install -m 644 -o "$UTILIZADOR" -g "$UTILIZADOR" "$TMP_PAGINA" "$CASA/semaforo/index.html"
rm -f "$TMP_PAGINA"

install -d /usr/local/lib/semaforo
TMP_SRV="$(mktemp)"
obter servidor.py "$TMP_SRV"
python3 -m py_compile "$TMP_SRV" || { echo "O servidor.py tem erros."; exit 1; }
install -m 755 "$TMP_SRV" /usr/local/lib/semaforo/servidor.py
rm -f "$TMP_SRV"

# --- 5. PIN do telemóvel ---------------------------------------------------------
F_PIN="$CASA/semaforo-dados/pin"
if [ ! -s "$F_PIN" ]; then
  echo
  echo ">> Define o PIN para alterar as definições pelo telemóvel (4 a 8 algarismos)."
  while true; do
    read -rsp "   PIN: " PIN1; echo
    read -rsp "   Repete o PIN: " PIN2; echo
    if [ "$PIN1" = "$PIN2" ] && printf '%s' "$PIN1" | grep -Eq '^[0-9]{4,8}$'; then break; fi
    echo "   Os PIN não coincidem ou não têm 4 a 8 algarismos. Tenta outra vez."
  done
  printf '%s\n' "$PIN1" > "$F_PIN"
  unset PIN1 PIN2
fi
chown "$UTILIZADOR":"$UTILIZADOR" "$F_PIN"; chmod 600 "$F_PIN"

# --- 6. Serviço do servidor local (porta 80, sem ser administrador) -------------
cat > /etc/systemd/system/semaforo-servidor.service <<EOF
[Unit]
Description=Semáforo sonoro — servidor local (ecrã e telemóvel)
After=network.target

[Service]
User=$UTILIZADOR
Environment=SEMAFORO_PORTA=80
Environment=SEMAFORO_CASA=$CASA
ExecStart=/usr/bin/python3 /usr/local/lib/semaforo/servidor.py
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable semaforo-servidor.service
systemctl restart semaforo-servidor.service

# --- 7. Entrar automaticamente no terminal 1 ------------------------------------
install -d /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $UTILIZADOR --noclear %I \$TERM
EOF

# --- 8. Arrancar o modo gráfico ao entrar ---------------------------------------
cat > "$CASA/.bash_profile" <<'EOF'
# Arranca o semáforo apenas no terminal 1 (os outros terminais ficam livres para manutenção)
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx -- -nolisten tcp vt1 >/dev/null 2>&1
fi
EOF

cat > "$CASA/.xinitrc" <<'EOF'
#!/bin/sh
# Ecrã sempre ligado
xset s off
xset s noblank
xset -dpms

# Esconde o cursor do rato ao fim de 3 s parado
unclutter -idle 3 &

# Escreve o IP para a página (ip.js), de 30 em 30 s
semaforo-ip &

# Desliga o PC quando a página o pede (às horas definidas nas definições)
semaforo-vigia-desligar &

# Atualiza a página a partir do GitHub (só no arranque; se falhar, fica a versão anterior)
semaforo-atualizar-pagina

# Uma só vez: passa as definições antigas (guardadas no browser) para o ficheiro do PC
if [ ! -f "$HOME/semaforo-dados/definicoes.json" ] && [ -d "$HOME/.config/chromium" ]; then
  timeout 40 chromium --headless=new --disable-gpu --no-first-run \
    --user-data-dir="$HOME/.config/chromium" --virtual-time-budget=6000 \
    --dump-dom "file://$HOME/semaforo/index.html?migrar=1" >/dev/null 2>&1 || true
fi

# Espera pelo servidor local (até 15 s); se não responder, abre a página diretamente do disco
URL="file://$HOME/semaforo/index.html?auto=1"
i=0
while [ $i -lt 30 ]; do
  if curl -fs -o /dev/null --max-time 1 http://127.0.0.1/index.html; then URL="http://127.0.0.1/index.html?auto=1"; break; fi
  sleep 0.5; i=$((i+1))
done

# Resolução atual do ecrã (ex.: 1920,1080)
TAM="$(xrandr 2>/dev/null | awk '/\*/{print $1; exit}' | tr x ,)"
[ -n "$TAM" ] || TAM="1920,1080"

PREFS="$HOME/.config/chromium/Default/Preferences"

# Se o Chromium fechar ou falhar, volta a abrir
while true; do
  # evita o aviso "o Chromium não foi encerrado corretamente"
  [ -f "$PREFS" ] && sed -i 's/"exited_cleanly":false/"exited_cleanly":true/; s/"exit_type":"[^"]*"/"exit_type":"Normal"/' "$PREFS"
  chromium \
    --kiosk \
    --window-position=0,0 \
    --window-size="$TAM" \
    --no-first-run \
    --noerrdialogs \
    --disable-infobars \
    --hide-crash-restore-bubble \
    --disable-translate \
    --disable-features=Translate \
    --password-store=basic \
    --check-for-update-interval=31536000 \
    --autoplay-policy=no-user-gesture-required \
    --use-fake-ui-for-media-stream \
    --allow-file-access-from-files \
    "$URL"
  sleep 2
done
EOF
chmod +x "$CASA/.xinitrc"
chown "$UTILIZADOR":"$UTILIZADOR" "$CASA/.bash_profile" "$CASA/.xinitrc"

# --- 9. Botão de ligar = encerrar o sistema de forma segura ---------------------
install -d /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/semaforo.conf <<'EOF'
[Login]
HandlePowerKey=poweroff
HandlePowerKeyLongPress=poweroff
EOF

# --- 10. Autorização para desligar o PC (só isto) -------------------------------
TMP_SUDO="$(mktemp)"
echo "$UTILIZADOR ALL=(root) NOPASSWD: /usr/bin/systemctl poweroff" > "$TMP_SUDO"
if visudo -cf "$TMP_SUDO" >/dev/null; then
  install -m 440 "$TMP_SUDO" /etc/sudoers.d/semaforo-desligar
else
  echo "Aviso: não foi possível configurar o desligar automático."
fi
rm -f "$TMP_SUDO"

# --- 11. Comandos auxiliares ----------------------------------------------------
cat > /usr/local/bin/semaforo-vigia-desligar <<'EOF'
#!/bin/sh
# Desliga o PC quando o servidor local cria o ficheiro "desligar-agora" (pedido da página à hora marcada)
F="$HOME/semaforo-dados/desligar-agora"
rm -f "$F"
while true; do
  if [ -f "$F" ]; then
    rm -f "$F"
    sudo -n /usr/bin/systemctl poweroff
  fi
  sleep 2
done
EOF

cat > /usr/local/bin/semaforo-ip <<'EOF'
#!/bin/sh
# Escreve o IP atual num ficheiro que a página do semáforo lê de 30 em 30 s
while true; do
  IP="$(hostname -I | awk '{print $1}')"
  echo "window.SEMAFORO_IP=\"$IP\";" > "$HOME/semaforo/ip.js"
  sleep 30
done
EOF

cat > /usr/local/bin/semaforo-atualizar-pagina <<EOF
#!/bin/sh
# Descarrega a versão mais recente da página do GitHub (corre no arranque, antes de abrir o ecrã).
# Só substitui se o ficheiro vier completo; guarda a versão anterior em index.anterior.html.
URL_API="$GITHUB_API/semaforo-sonoro-teste.html?ref=main"
URL_RAW="$GITHUB/semaforo-sonoro-teste.html"
EOF
cat >> /usr/local/bin/semaforo-atualizar-pagina <<'EOF'
DEST="$HOME/semaforo/index.html"
LOG="$HOME/semaforo-dados/atualizacao.log"
# espera pela rede até 15 s
i=0
while [ $i -lt 15 ] && ! ip route 2>/dev/null | grep -q '^default'; do sleep 1; i=$((i+1)); done
TMP="$(mktemp)"
# 1.º o API do GitHub (funciona na escola); se falhar, o endereço direto
descarregar() {
  curl -fsSL --max-time 20 -H "Accept: application/vnd.github.raw" "$URL_API" -o "$TMP" \
    || curl -fsSL --max-time 20 "$URL_RAW" -o "$TMP"
}
if descarregar \
   && [ "$(wc -c < "$TMP")" -gt 20000 ] \
   && grep -q 'SEMAFORO_PAGINA_OK' "$TMP" && grep -q '</html>' "$TMP"; then
  if cmp -s "$TMP" "$DEST"; then
    echo "$(date '+%F %T') sem alterações" >> "$LOG"
  else
    cp -p "$DEST" "$HOME/semaforo/index.anterior.html" 2>/dev/null || true
    cp "$TMP" "$DEST.novo" && mv "$DEST.novo" "$DEST"
    echo "$(date '+%F %T') página atualizada" >> "$LOG"
  fi
else
  echo "$(date '+%F %T') não foi possível atualizar (fica a versão anterior)" >> "$LOG"
fi
rm -f "$TMP"
tail -n 50 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
exit 0
EOF

cat > /usr/local/bin/semaforo-audio <<EOF
#!/bin/sh
# Controla o áudio da sessão do semáforo (usar com sudo). Exemplos:
#   semaforo-audio status                                     (lista saídas e microfones, com números)
#   semaforo-audio set-default 45                             (escolhe o dispositivo n.º 45)
#   semaforo-audio set-volume @DEFAULT_AUDIO_SOURCE@ 30%      (ganho do microfone)
exec runuser -u $UTILIZADOR -- env XDG_RUNTIME_DIR=/run/user/$UID_U wpctl "\$@"
EOF

cat > /usr/local/bin/semaforo-pactl <<EOF
#!/bin/sh
# pactl na sessão do semáforo (usar com sudo)
exec runuser -u $UTILIZADOR -- env XDG_RUNTIME_DIR=/run/user/$UID_U pactl "\$@"
EOF

cat > /usr/local/bin/semaforo-hdmi <<'EOF'
#!/bin/sh
# Põe o som a sair pelo ecrã (HDMI/DisplayPort), mantendo o microfone analógico. (usar com sudo)
# NOTA: na escola o som sai pela saída analógica traseira — aí NÃO se usa este comando.
PLACA="$(semaforo-pactl list cards short | awk 'NR==1{print $2}')"
PERFIL="$(semaforo-pactl list cards | grep -E 'output:hdmi-stereo(-extra[0-9]+)?\+input:analog-stereo:.*available: yes' | head -n1 | sed -E 's/^[[:space:]]*([^[:space:]]+): .*/\1/')"
if [ -z "$PLACA" ] || [ -z "$PERFIL" ]; then
  echo "Não encontrei uma saída HDMI ligada."; exit 1
fi
semaforo-pactl set-card-profile "$PLACA" "$PERFIL" && echo "Som pelo ecrã ativado: $PLACA -> $PERFIL"
EOF

cat > /usr/local/bin/semaforo-analogico <<'EOF'
#!/bin/sh
# Põe o som a sair pelas fichas analógicas (traseira/frente), com o microfone analógico. (usar com sudo)
PLACA="$(semaforo-pactl list cards short | awk 'NR==1{print $2}')"
semaforo-pactl set-card-profile "$PLACA" output:analog-stereo+input:analog-stereo && echo "Som pela saída analógica ativado."
EOF

cat > /usr/local/bin/semaforo-atualizar <<EOF
#!/bin/sh
# Instala à mão uma página (ex.: copiada por scp) e reinicia o ecrã.  Uso: sudo semaforo-atualizar ~/semaforo-sonoro-teste.html
[ -f "\$1" ] || { echo "Uso: sudo semaforo-atualizar /caminho/pagina.html"; exit 1; }
grep -q 'SEMAFORO_PAGINA_OK' "\$1" || { echo "Ficheiro incompleto (falta a marca final). Não instalado."; exit 1; }
cp -p "$CASA/semaforo/index.html" "$CASA/semaforo/index.anterior.html" 2>/dev/null || true
install -m 644 -o $UTILIZADOR -g $UTILIZADOR "\$1" "$CASA/semaforo/index.html"
pkill -u $UTILIZADOR chromium || true
echo "Página instalada. O ecrã reabre sozinho em poucos segundos."
EOF

cat > /usr/local/bin/semaforo-pin <<EOF
#!/bin/sh
# Muda o PIN do telemóvel (usar com sudo).
[ "\$(id -u)" -eq 0 ] || { echo "Usa: sudo semaforo-pin"; exit 1; }
printf "Novo PIN (4 a 8 algarismos): "; stty -echo; read P1; stty echo; echo
printf "Repete: "; stty -echo; read P2; stty echo; echo
if [ "\$P1" != "\$P2" ] || ! printf '%s' "\$P1" | grep -Eq '^[0-9]{4,8}\$'; then echo "Não alterado."; exit 1; fi
printf '%s\n' "\$P1" > "$CASA/semaforo-dados/pin"
chown $UTILIZADOR:$UTILIZADOR "$CASA/semaforo-dados/pin"; chmod 600 "$CASA/semaforo-dados/pin"
echo "PIN alterado."
EOF

chmod +x /usr/local/bin/semaforo-ip /usr/local/bin/semaforo-vigia-desligar /usr/local/bin/semaforo-atualizar-pagina /usr/local/bin/semaforo-audio \
  /usr/local/bin/semaforo-pactl /usr/local/bin/semaforo-hdmi /usr/local/bin/semaforo-analogico \
  /usr/local/bin/semaforo-atualizar /usr/local/bin/semaforo-pin

# --- 12. Arranque mais rápido (menu do GRUB quase invisível) --------------------
if [ -f /etc/default/grub ]; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
  update-grub || true
fi

IP="$(hostname -I | awk '{print $1}')"
echo
echo "================================================================"
echo " Instalação concluída (v5). Reinicia com:  sudo reboot"
echo " - O computador arranca diretamente para o semáforo."
echo " - Telemóvel (na mesma rede):  http://$IP   (pede o PIN)"
echo " - Em cada arranque a página atualiza-se sozinha a partir do GitHub."
echo " - Manutenção: Ctrl+Alt+F2 abre um terminal; Ctrl+Alt+F1 volta."
echo " - Som: sai pela saída analógica. Só se quiseres pelo ecrã: sudo semaforo-hdmi"
echo "================================================================"

#!/usr/bin/env bash
# Servidor do AccViewer na nuvem (Oracle Cloud "Always Free", Ubuntu).
# Instala o RustDesk Server 1.1.16 oficial com a MESMA chave e as MESMAS portas
# do servidor que estava na maquina virtual da Accuracy, para nenhum PC precisar
# ser reconfigurado: depois e so apontar o acesso.accuracyautomation.com para o
# IP desta maquina.
#
# Uso, dentro da maquina da nuvem (SSH):
#   curl -fsSL https://raw.githubusercontent.com/viniking58/accviewer/accviewer/accviewer-marca/servidor-nuvem.sh -o servidor-nuvem.sh
#   sudo bash servidor-nuvem.sh
# Ele pede para colar o conteudo do id_ed25519 (a chave secreta), que fica em
# C:\Program Files\RustDesk Server na maquina virtual.
set -euo pipefail

VERSAO="1.1.16"
ENDERECO="acesso.accuracyautomation.com"
PORTA_ID=2091
PORTA_RELAY=2095
CHAVE_PUBLICA="41qeq2fo4ovjhQWg6RNg65loXG2tlowcWcDy+a4hiIQ="
PASTA=/opt/accviewer-servidor

[ "$(id -u)" -eq 0 ] || { echo "Rode com sudo: sudo bash servidor-nuvem.sh"; exit 1; }

case "$(uname -m)" in
  x86_64)  PACOTE=rustdesk-server-linux-amd64.zip;   SHA=0565c41affe6c3f409b0bddfaf5a24ccbf3f64f5f8e3fec250b69a0d5f6bdbcf ;;
  aarch64) PACOTE=rustdesk-server-linux-arm64v8.zip; SHA=6a4ae3c5ca257a4278ded72fd17eb2ca4eeb0356a5425e63a3e7fcb0ec6c155c ;;
  *) echo "Processador nao suportado: $(uname -m)"; exit 1 ;;
esac

echo
echo "  1. Baixando o RustDesk Server $VERSAO oficial ($PACOTE)"
apt-get update -qq >/dev/null
apt-get install -y -qq unzip curl >/dev/null
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/$PACOTE" "https://github.com/rustdesk/rustdesk-server/releases/download/$VERSAO/$PACOTE"
echo "$SHA  $tmp/$PACOTE" | sha256sum -c --quiet - || { echo "O arquivo baixado nao confere com o oficial."; exit 1; }
unzip -q -o "$tmp/$PACOTE" -d "$tmp/x"
hbbs=$(find "$tmp/x" -type f -name hbbs | head -1)
hbbr=$(find "$tmp/x" -type f -name hbbr | head -1)
[ -n "$hbbs" ] && [ -n "$hbbr" ] || { echo "O pacote veio sem hbbs/hbbr."; exit 1; }

echo "  2. Instalando em $PASTA"
id accviewer >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin accviewer
systemctl stop accviewer-hbbs accviewer-hbbr 2>/dev/null || true
mkdir -p "$PASTA"
install -m 755 "$hbbs" "$PASTA/hbbs"
install -m 755 "$hbbr" "$PASTA/hbbr"
rm -rf "$tmp"

echo "  3. Chave da Accuracy"
if [ -f "$PASTA/id_ed25519" ] && [ "$(tr -d '\r\n ' < "$PASTA/id_ed25519.pub")" = "$CHAVE_PUBLICA" ]; then
  echo "     ja instalada"
else
  echo "     Abra C:\\Program Files\\RustDesk Server\\id_ed25519 (sem .pub) no Bloco de Notas"
  echo "     da maquina virtual, copie TODO o texto e cole aqui (nao aparece nada) + Enter:"
  read -r -s SECRETA
  SECRETA=$(printf '%s' "$SECRETA" | tr -d '\r\n ')
  [ -n "$SECRETA" ] || { echo "Nada colado."; exit 1; }
  # A chave secreta ed25519 (64 bytes) termina com a chave publica (32 bytes).
  PUB=$(printf '%s' "$SECRETA" | base64 -d 2>/dev/null | tail -c 32 | base64 -w0)
  [ "$PUB" = "$CHAVE_PUBLICA" ] || { echo "Essa nao e a chave da Accuracy (a publica nao confere). Nada foi trocado."; exit 1; }
  printf '%s' "$SECRETA" > "$PASTA/id_ed25519"
  printf '%s' "$CHAVE_PUBLICA" > "$PASTA/id_ed25519.pub"
  unset SECRETA
  echo "     ok (confere com a chave publica da Accuracy)"
fi
chown -R accviewer:accviewer "$PASTA"
chmod 600 "$PASTA/id_ed25519"

echo "  4. Ligando junto com a maquina (systemd)"
cat > /etc/systemd/system/accviewer-hbbs.service <<EOF
[Unit]
Description=AccViewer - servidor de ID (hbbs)
After=network-online.target
Wants=network-online.target

[Service]
User=accviewer
WorkingDirectory=$PASTA
ExecStart=$PASTA/hbbs -p $PORTA_ID -r $ENDERECO:$PORTA_RELAY -k _
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/accviewer-hbbr.service <<EOF
[Unit]
Description=AccViewer - retransmissao (hbbr)
After=network-online.target accviewer-hbbs.service
Wants=network-online.target

[Service]
User=accviewer
WorkingDirectory=$PASTA
ExecStart=$PASTA/hbbr -p $PORTA_RELAY -k _
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now accviewer-hbbs accviewer-hbbr >/dev/null 2>&1

echo "  5. Liberando as portas no firewall da maquina"
# As imagens Ubuntu da Oracle bloqueiam tudo no iptables, menos o SSH.
regra() { iptables -C INPUT -p "$1" --dport "$2" -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p "$1" --dport "$2" -j ACCEPT; }
regra tcp $((PORTA_ID - 1))
regra tcp $PORTA_ID
regra udp $PORTA_ID
regra tcp $PORTA_RELAY
if command -v netfilter-persistent >/dev/null; then netfilter-persistent save >/dev/null 2>&1; fi

sleep 3
echo
ok=1
for p in $((PORTA_ID - 1)) $PORTA_ID $PORTA_RELAY; do
  ss -ltn "sport = :$p" | grep -q LISTEN || { echo "  ATENCAO: porta TCP $p nao abriu"; ok=0; }
done
ss -lun "sport = :$PORTA_ID" | grep -q ":$PORTA_ID" || { echo "  ATENCAO: porta UDP $PORTA_ID nao abriu"; ok=0; }
IP=$(curl -fsS -m 10 https://api.ipify.org || echo "?")
echo "  ===================================================================="
[ $ok = 1 ] && echo "   SERVIDOR DO ACCVIEWER NO AR" || echo "   VEJA OS AVISOS ACIMA: systemctl status accviewer-hbbs accviewer-hbbr"
echo "  ===================================================================="
echo "   IP publico desta maquina: $IP"
echo "   No Wix: o registro 'acesso' passa a ser A -> $IP"
echo "   Na Oracle (Security List da rede): liberar TCP 2090-2091, TCP 2095"
echo "   e UDP 2091, origem 0.0.0.0/0."
echo

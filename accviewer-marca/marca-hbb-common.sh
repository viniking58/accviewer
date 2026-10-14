#!/usr/bin/env bash
# AccViewer: nome, servidor e chave da Accuracy embutidos no programa.
# O libs/hbb_common e um submodulo (outro repositorio), por isso a troca e
# feita aqui, durante a compilacao, logo depois do checkout.
# Falha se nao achar o que trocar: melhor parar do que gerar um programa que
# aponta para o servidor publico do RustDesk.
set -euo pipefail

NOME="AccViewer"
SERVIDOR="acesso.accuracyautomation.com:2091"
CHAVE="41qeq2fo4ovjhQWg6RNg65loXG2tlowcWcDy+a4hiIQ="

cfg="libs/hbb_common/src/config.rs"

sed -i -e "/APP_NAME: RwLock<String>/s|\"RustDesk\"|\"$NOME\"|" "$cfg"
sed -i -e "s|\"rs-ny.rustdesk.com\"|\"$SERVIDOR\"|" "$cfg"
# Servidor "de producao": com ele o programa sabe que nao esta no servidor
# publico do RustDesk (sem o aviso "configure seu proprio servidor" e sem os
# limites de qualidade/FPS do servidor publico).
sed -i -e "/PROD_RENDEZVOUS_SERVER: RwLock<String>/s|RwLock::new(\"\".to_owned())|RwLock::new(\"$SERVIDOR\".to_owned())|" "$cfg"
sed -i -e "s|\"OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=\"|\"$CHAVE\"|" "$cfg"

grep -q "APP_NAME: RwLock<String> = RwLock::new(\"$NOME\"" "$cfg" || { echo "AccViewer: APP_NAME nao trocado"; exit 1; }
grep -q "RENDEZVOUS_SERVERS: &\[&str\] = &\[\"$SERVIDOR\"\]" "$cfg" || { echo "AccViewer: servidor nao trocado"; exit 1; }
grep -qF "RS_PUB_KEY: &str = \"$CHAVE\"" "$cfg" || { echo "AccViewer: chave nao trocada"; exit 1; }
grep -qF "PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new(\"$SERVIDOR\"" "$cfg" || { echo "AccViewer: servidor de producao nao trocado"; exit 1; }
echo "AccViewer: nome, servidor e chave aplicados em $cfg"

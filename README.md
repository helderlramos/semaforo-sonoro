# Semáforo Sonoro

Semáforo de ruído para a cantina de uma escola do 1.º ciclo (Madeira). Um PC com Debian, um microfone e um ecrã:
mede o ruído, mostra verde / laranja / vermelho e, quando o barulho se mantém alto, toca um aviso e mostra
"Fazer silêncio" com uma contagem.

O som é apenas analisado em tempo real: **nada é gravado nem enviado**.

## Ficheiros

| Ficheiro | Descrição |
|---|---|
| `semaforo-sonoro-teste.html` | A página do semáforo (ecrã em modo quiosque + página de definições para telemóvel). Os PCs instalados descarregam esta versão em cada arranque. |
| `servidor.py` | Servidor local (Python, sem dependências) que serve a página e guarda as definições. |
| `instalar-semaforo.sh` | Instalação num Debian 13: arranque automático, Chromium em ecrã inteiro, servidor, PIN, atualização automática. |
| `guia-instalacao-semaforo.md` | Guia passo a passo de instalação e manutenção. |

## Instalação rápida

```
sudo bash instalar-semaforo.sh
sudo reboot
```

Ver o [guia](guia-instalacao-semaforo.md) para os detalhes.

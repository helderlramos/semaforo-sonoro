# Semáforo Sonoro — guia de instalação e manutenção

**Versão 3 — 29/09/2026.** Substitui a versão 2. Novidades: definições pelo telemóvel, atualização automática da página a partir do GitHub, ecrã "Fazer silêncio", som pela saída analógica (escola), uso de `sudo`.

Ficheiros oficiais: **https://github.com/helderlramos/semaforo-sonoro** (público). Cópias no Google Drive, pasta `Echo/Semáforo`.

---

## 1. Como funciona

- **Botão de ligar →** o PC arranca, entra sozinho na conta `semaforo` e abre o semáforo em ecrã inteiro (20–40 s).
- **Botão outra vez (pressão curta) →** o PC desliga-se corretamente.
- Em cada arranque, **antes de abrir o ecrã**, o PC vai buscar ao GitHub a versão mais recente da página. Só a substitui se vier completa; se falhar (sem internet, por exemplo), fica a versão anterior. Guarda a versão anterior em `index.anterior.html`. Nunca atualiza a meio do almoço.
- **Definições pelo telemóvel:** no browser do telemóvel, na mesma rede, abre `http://IP-do-PC` (o IP aparece no canto inferior esquerdo do ecrã). Pede o PIN definido na instalação.
- **Duas contas:**
  - `semaforo` — sem password nem permissões de administrador; corre o ecrã e o servidor local.
  - a tua conta (ex.: `helder`) — administrador com `sudo`, só para manutenção.
- O script de sistema (`instalar-semaforo.sh`) **não** se atualiza sozinho: quando houver versão nova, corre-se à mão (secção 7).

## 2. Material

- PC de 64 bits (Intel/AMD). SSD recomendado.
- Ecrã/TV com HDMI (ou DisplayPort).
- **Colunas ligadas à saída de áudio analógica traseira** (verde) — é por aí que sai o som na escola.
- Microfone Boya BY-MM1 na **ficha de microfone (rosa)**, com o **cabo de 3 anéis (TRS)**.
- Pen USB de 2 GB (instalador), teclado e rato (só para instalar), internet por cabo ou Wi-Fi.
- Um computador com Windows para descarregar os ficheiros e fazer SSH. Um telemóvel para as definições.

## 3. Ficheiros

| Ficheiro | Para quê |
|---|---|
| `instalar-semaforo.sh` | Script que transforma o Debian no semáforo (**v4**) |
| `semaforo-sonoro-teste.html` | A página do semáforo (ecrã + modo telemóvel). Versão visível no canto do ecrã (ex.: `v2026-09-29`) |
| `servidor.py` | Servidor local (página do telemóvel e definições partilhadas) |
| `guia-instalacao-semaforo.md` | Este guia |

## 4. Preparar o PC

1. **Verificar o hardware** se o PC for usado: "Input/output error" no instalador = disco avariado; erros de "hash não coincide" diferentes a cada tentativa = suspeitar da RAM (memtest86+).
2. **BIOS/UEFI:** arranque em UEFI. Opcional: *After Power Loss → Power On*.
3. **Pen do instalador:** Debian 13 netinst amd64 (https://www.debian.org/download), gravada com Rufus ou balenaEtcher.

## 5. Instalar o Debian 13

| Pergunta | Resposta |
|---|---|
| Idioma / país / teclado | Português / Portugal / Português |
| Nome da máquina | `semaforo` (ou outro) — domínio vazio |
| **Palavra-passe do root** | **Deixa vazia** → a tua conta fica logo com `sudo`. (Se definires uma, ver 11.2.) |
| Utilizador | O teu (ex.: `helder`). **Não** uses `semaforo`. |
| Discos | Guiado – usar o disco inteiro |
| Seleção de software | **Ambiente de trabalho Debian + Xfce**, **Servidor SSH**, **Utilitários standard** |

## 6. Primeiro arranque (por SSH)

No Windows (PowerShell): `ssh helder@IP_DO_PC`. No Debian:
```
sudo whoami
```
Deve responder `root`. Depois:
```
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

> **Duas janelas diferentes:** `scp` corre no PowerShell do Windows (`PS C:\...>`); o resto corre na janela do SSH (`helder@...$`). **Um comando de cada vez.**

## 7. Instalar (ou atualizar) o semáforo

**7.1 Copiar os ficheiros** — PowerShell no Windows, na pasta onde estão os 3 ficheiros:
```
dir *.sh, *.html, *.py
scp instalar-semaforo.sh semaforo-sonoro-teste.html servidor.py helder@IP_DO_PC:~/
```
Confirma os tamanhos: devem ser iguais aos do GitHub. Se o Windows mudar os nomes para "(1)", apaga os antigos primeiro.

**7.2 Correr o script** — janela do SSH:
```
sed -i 's/\r$//' ~/instalar-semaforo.sh
sudo bash ~/instalar-semaforo.sh
```
Na primeira vez pede o **PIN do telemóvel** (4 a 8 algarismos). No fim mostra o endereço para o telemóvel.

**7.3 Reiniciar** com o microfone e as colunas ligados: `sudo reboot`.

> Na primeira vez que corre a v4 num PC que já tinha o semáforo, as definições antigas (limites, textos, sons) passam automaticamente do browser para o ficheiro do PC.

## 8. Som e microfone

**8.1 Confirmar** (janela do SSH):
```
sudo semaforo-audio status
```
Em **Sinks** deve haver `*` na saída **Analógica**; em **Sources**, `*` no microfone analógico. Se faltar, escolhe pelo número: `sudo semaforo-audio set-default NÚMERO`.

- Se o som sair pela TV em vez das colunas: `sudo semaforo-analogico`.
- Só se quiseres o som pelo ecrã/TV: `sudo semaforo-hdmi` (**não usar na escola**).

**8.2 Volumes:**
```
sudo semaforo-audio set-volume @DEFAULT_AUDIO_SINK@ 100%
sudo semaforo-audio set-volume @DEFAULT_AUDIO_SOURCE@ 50%
```
O volume do alarme ajusta-se depois nas definições. Se aparecer "Saturação", baixa o ganho do microfone (40%, 30%, 25%…). **Depois de calibrar, não voltes a mexer no ganho.**

**8.3 Testar:** tecla **T** no PC, ou "Testar alarme" no telemóvel.

## 9. Telemóvel

1. Liga o telemóvel à **mesma rede** do PC.
2. Abre `http://IP_DO_PC` (sem `https`). Guarda como favorito/atalho no ecrã inicial.
3. Escreve o PIN. Aparece: estado ao vivo (dB, cor, "Fazer silêncio"), botões **Testar alarme / Cancelar alarme / Repor tempo extra**, e todas as definições. Carrega em **Guardar alterações** — o ecrã atualiza em poucos segundos.
4. A **calibração** só se faz no PC (tecla S), com o sonómetro ao lado.
5. Mudar o PIN: `sudo semaforo-pin`.

Se o telemóvel não abrir a página: confirma que está na mesma rede e que o IP é o do canto do ecrã. Algumas redes de convidados bloqueiam a ligação entre aparelhos — nesse caso usa outra rede ou o teclado.

## 10. Definições e calibração

**10.1 Calibrar** (no PC, tecla S → Calibração): com ruído constante, escreve o valor do sonómetro (ou app em dBA) e carrega em **Calibrar**. Sem sonómetro, os valores são relativos — servem de referência, mas não são dB reais.

**10.2 Ponto de partida** (não oficial): Laranja 70 dB · Vermelho 78 dB · Margem 3 dB · Média 3–5 s · Tocar após 5 s · Gráfico 60 min.

**10.3 Ecrã "Fazer silêncio":** quando o alarme dispara, tapa tudo, a piscar, com uma contagem de 5 min (texto e duração ajustáveis; pode ser desligado). Se voltar a haver barulho durante a contagem, o alarme toca de novo e a contagem recomeça. **C** cancela (ou "Cancelar alarme" no telemóvel).

**10.4 Repor:** "Repor definições" repõe tudo **exceto a calibração**; "Repor calibração" (secção Calibração) repõe só a calibração.

**10.5 Onde ficam:** num ficheiro no PC (`/home/semaforo/semaforo-dados/definicoes.json`), partilhado pelo ecrã e pelo telemóvel. As atualizações da página não apagam as definições.

## 11. Resolução de problemas

| Problema | Solução |
|---|---|
| **11.1** "Input/output error" no instalador | Disco avariado — trocar |
| **11.2** `sudo`: "não está no ficheiro sudoers" | `su -` → `apt install sudo` → `usermod -aG sudo helder` → `exit` → `exit` → voltar a ligar por SSH |
| **11.3** `runuser: not found` | Faltou `sudo` antes do comando |
| **11.4** "hash não coincide" (valores diferentes) | RAM com defeito |
| **11.5** "Requested device not found" | Microfone na ficha errada — ficha rosa, cabo TRS |
| **11.6** Saturação | Baixar o ganho (8.2) |
| **11.7** Meio ecrã / sem IP no canto | Versão antiga do script: confirmar tamanhos (7.1) e correr o script outra vez |
| **11.8** Instalou-se a versão errada | Ver os tamanhos com `wc -c ~/instalar-semaforo.sh ~/semaforo-sonoro-teste.html` e comparar com o GitHub |
| **11.9** A página não se atualizou | `sudo cat /home/semaforo/semaforo-dados/atualizacao.log` — mostra se houve internet no arranque |
| **11.10** Voltar à versão anterior da página | `sudo semaforo-atualizar /home/semaforo/semaforo/index.anterior.html` (só até ao próximo arranque com internet) |
| **11.11** Telemóvel: "PIN errado" | `sudo semaforo-pin` para definir outro |
| **11.12** Telemóvel: "Sem ligação ao ecrã" | O ecrã não está a correr — `sudo systemctl status semaforo-servidor` e reiniciar o PC |
| **11.13** SSH: aviso de identificação alterada | No Windows: `ssh-keygen -R IP` |
| **11.14** Colar vários comandos de uma vez com `su -` | O `su` "engole" as linhas seguintes — um comando de cada vez |

## 12. Utilização e manutenção

**Teclas:** **S** definições · **T** testar/parar alarme · **C** cancelar "Fazer silêncio" · **I** mostrar/esconder IP · **F** ecrã inteiro · **Esc** fechar.

**No PC:** Ctrl+Alt+F2 abre um terminal; Ctrl+Alt+F1 volta ao semáforo.

| Comando (SSH) | Faz |
|---|---|
| `sudo semaforo-audio status` | Lista saídas e entradas de som |
| `sudo semaforo-audio set-default N` | Escolhe o dispositivo N |
| `sudo semaforo-audio set-volume @DEFAULT_AUDIO_SOURCE@ 50%` | Ganho do microfone |
| `sudo semaforo-analogico` / `sudo semaforo-hdmi` | Som pelas colunas / pelo ecrã |
| `sudo semaforo-pin` | Muda o PIN do telemóvel |
| `sudo semaforo-atualizar FICHEIRO.html` | Instala uma página à mão |
| `sudo cat /home/semaforo/semaforo-dados/atualizacao.log` | Histórico das atualizações automáticas |
| `sudo pkill -u semaforo chromium` | Reinicia o ecrã (reabre em 2–3 s) |
| `sudo apt update && sudo apt full-upgrade -y` | Atualizações do sistema |

## 13. Regras para versões novas da página (para quem as prepara)

- Nunca mudar o nome de gravação `semaforo-sonoro-cfg-v1`, nem o nome ou as unidades das definições existentes.
- Ajustar os valores por defeito (`DEF`) para valores próximos dos pretendidos.
- Manter a marca `SEMAFORO_PAGINA_OK` no fim do ficheiro (sem ela, o PC não instala a página).
- Atualizar `VERSAO` no início do código.
- Publicar no GitHub (`main`). Os PCs instalam no arranque seguinte.

## 14. Pendente

- Estatísticas e gráfico não são guardados quando o PC desliga.
- Sirene de 12 V (ESP32) ainda não ligada.
- M710q: correr o memtest86+.

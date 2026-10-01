#!/usr/bin/env python3
# =============================================================================
#  Semáforo Sonoro — servidor local
#  - serve a página do semáforo ao próprio PC (http://127.0.0.1/)
#  - serve a página de definições ao telemóvel (http://IP-do-PC/), protegida por PIN
#  - guarda as definições num ficheiro (definicoes.json), partilhado pelos dois
#  Corre na conta "semaforo" (sem permissões de administrador).
# =============================================================================
import json, os, sys, threading, time, hmac
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

PORTA   = int(os.environ.get('SEMAFORO_PORTA', '80'))
CASA    = os.path.expanduser(os.environ.get('SEMAFORO_CASA', '~'))
PAGINAS = os.path.join(CASA, 'semaforo')            # index.html e ip.js
DADOS   = os.path.join(CASA, 'semaforo-dados')      # definicoes.json, audio.json, pin
F_CFG   = os.path.join(DADOS, 'definicoes.json')
F_AUDIO = os.path.join(DADOS, 'audio.json')
F_PIN   = os.path.join(DADOS, 'pin')
F_EXTRA = os.path.join(DADOS, 'extra-migrado.json')
F_DESLIGAR = os.path.join(DADOS, 'desligar-agora')

# definições que só podem ser alteradas no próprio PC (não pelo telemóvel)
SO_NO_PC = {'offset', 'dispositivo'}
COMANDOS = {'testar', 'cancelar', 'reporExtra'}
MAX_CORPO = 12 * 1024 * 1024      # 12 MB (ficheiros de áudio)

bloqueio = threading.Lock()
estado = {'cfg': {}, 'rev': 0, 'cmds': [], 'ultimoCmd': 0, 'ecra': None, 'ecraHora': 0.0}

def ler_json(caminho, omissao):
    try:
        with open(caminho, encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return omissao

def gravar_json(caminho, dados):
    os.makedirs(DADOS, exist_ok=True)
    tmp = caminho + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(dados, f, ensure_ascii=False, indent=1)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, caminho)            # troca atómica: nunca fica um ficheiro a meio

def ler_pin():
    try:
        with open(F_PIN, encoding='utf-8') as f:
            return f.read().strip()
    except Exception:
        return ''

guardado = ler_json(F_CFG, {})
estado['cfg'] = guardado.get('cfg', {}) if isinstance(guardado, dict) else {}
estado['rev'] = int(guardado.get('rev', 0)) if isinstance(guardado, dict) else 0

def gravar_cfg():
    gravar_json(F_CFG, {'rev': estado['rev'], 'cfg': estado['cfg']})


class Pedido(BaseHTTPRequestHandler):
    server_version = 'Semaforo/1'

    def log_message(self, fmt, *args):
        pass                                    # sem registos (não guarda nada sobre quem acede)

    # ---------- utilitários ----------
    def local(self):
        return self.client_address[0] in ('127.0.0.1', '::1', '::ffff:127.0.0.1')

    def enviar(self, codigo, corpo=b'', tipo='application/json; charset=utf-8'):
        if isinstance(corpo, (dict, list)):
            corpo = json.dumps(corpo, ensure_ascii=False).encode('utf-8')
        elif isinstance(corpo, str):
            corpo = corpo.encode('utf-8')
        self.send_response(codigo)
        self.send_header('Content-Type', tipo)
        self.send_header('Content-Length', str(len(corpo)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(corpo)

    def ler_corpo(self):
        n = int(self.headers.get('Content-Length') or 0)
        if n > MAX_CORPO:
            raise ValueError('demasiado grande')
        dados = self.rfile.read(n) if n else b''
        return json.loads(dados.decode('utf-8') or '{}')

    def autorizado(self):
        if self.local():
            return True
        pin = ler_pin()
        dado = self.headers.get('X-PIN', '')
        if pin and hmac.compare_digest(pin, dado):
            return True
        time.sleep(1.0)                          # trava tentativas repetidas
        return False

    def ficheiro(self, nome, tipo):
        try:
            with open(os.path.join(PAGINAS, nome), 'rb') as f:
                self.enviar(200, f.read(), tipo)
        except FileNotFoundError:
            self.enviar(404, 'não encontrado', 'text/plain; charset=utf-8')

    # ---------- GET ----------
    def do_GET(self):
        caminho = self.path.split('?', 1)[0]
        if caminho == '/':
            self.send_response(302)
            self.send_header('Location', '/index.html?auto=1' if self.local() else '/index.html?remoto=1')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if caminho == '/index.html':
            return self.ficheiro('index.html', 'text/html; charset=utf-8')
        if caminho == '/ip.js':
            return self.ficheiro('ip.js', 'application/javascript; charset=utf-8')
        if caminho == '/api/config':
            if not self.autorizado():
                return self.enviar(401, {'erro': 'pin'})
            with bloqueio:
                return self.enviar(200, {'rev': estado['rev'], 'cfg': estado['cfg']})
        if caminho == '/api/estado':
            if not self.autorizado():
                return self.enviar(401, {'erro': 'pin'})
            with bloqueio:
                idade = time.time() - estado['ecraHora'] if estado['ecraHora'] else None
                return self.enviar(200, {'estado': estado['ecra'], 'idade': idade})
        if caminho == '/api/audio':
            if not self.local():
                return self.enviar(403, {'erro': 'só no PC'})
            a = ler_json(F_AUDIO, None)
            return self.enviar(200, a) if a else self.enviar(404, {'erro': 'sem áudio'})
        self.enviar(404, 'não encontrado', 'text/plain; charset=utf-8')

    do_HEAD = do_GET

    # ---------- POST ----------
    def do_POST(self):
        caminho = self.path.split('?', 1)[0]
        try:
            corpo = self.ler_corpo()
        except Exception:
            return self.enviar(400, {'erro': 'pedido inválido'})

        if caminho == '/api/config':
            if not self.autorizado():
                return self.enviar(401, {'erro': 'pin'})
            novo = corpo.get('cfg')
            if not isinstance(novo, dict):
                return self.enviar(400, {'erro': 'cfg em falta'})
            with bloqueio:
                for k, v in novo.items():
                    if not isinstance(k, str) or len(k) > 40:
                        continue
                    if k in SO_NO_PC and not self.local():
                        continue
                    if isinstance(v, (bool, int, float)) or (isinstance(v, str) and len(v) <= 500):
                        estado['cfg'][k] = v
                estado['rev'] += 1
                gravar_cfg()
                return self.enviar(200, {'rev': estado['rev']})

        if caminho == '/api/comando':
            if not self.autorizado():
                return self.enviar(401, {'erro': 'pin'})
            cmd = corpo.get('cmd')
            if cmd not in COMANDOS:
                return self.enviar(400, {'erro': 'comando desconhecido'})
            with bloqueio:
                estado['ultimoCmd'] += 1
                estado['cmds'].append({'id': estado['ultimoCmd'], 'cmd': cmd, 'hora': time.time()})
                estado['cmds'] = [c for c in estado['cmds'] if time.time() - c['hora'] < 60][-20:]
                return self.enviar(200, {'id': estado['ultimoCmd']})

        if caminho == '/api/sync':                      # só o ecrã do próprio PC
            if not self.local():
                return self.enviar(403, {'erro': 'só no PC'})
            with bloqueio:
                estado['ecra'] = corpo.get('estado')
                estado['ecraHora'] = time.time()
                resp = {'rev': estado['rev'], 'ultimoCmd': estado['ultimoCmd']}
                if int(corpo.get('rev') or 0) < estado['rev']:
                    resp['cfg'] = estado['cfg']
                ultimo = corpo.get('ultimoCmd')
                if isinstance(ultimo, (int, float)) and ultimo >= 0:
                    resp['cmds'] = [{'id': c['id'], 'cmd': c['cmd']} for c in estado['cmds'] if c['id'] > ultimo]
                else:
                    resp['cmds'] = []                   # ecrã acabado de abrir: ignora comandos antigos
                return self.enviar(200, resp)

        if caminho == '/api/audio':
            if not self.local():
                return self.enviar(403, {'erro': 'só no PC'})
            if not isinstance(corpo.get('dados'), str):
                return self.enviar(400, {'erro': 'dados em falta'})
            gravar_json(F_AUDIO, {'nome': str(corpo.get('nome', 'audio'))[:120], 'dados': corpo['dados']})
            return self.enviar(204)

        if caminho == '/api/desligar':                  # pedido do ecrã do próprio PC, à hora marcada
            if not self.local():
                return self.enviar(403, {'erro': 'só no PC'})
            with open(F_DESLIGAR, 'w') as f:            # o vigia (semaforo-vigia-desligar) desliga o PC
                f.write(time.strftime('%F %T'))
            return self.enviar(204)

        if caminho == '/api/migrar':                    # uma só vez: definições antigas do browser
            if not self.local():
                return self.enviar(403, {'erro': 'só no PC'})
            with bloqueio:
                cfg = corpo.get('cfg')
                if isinstance(cfg, dict) and not estado['cfg']:
                    estado['cfg'] = {k: v for k, v in cfg.items()
                                     if isinstance(k, str) and (isinstance(v, (bool, int, float)) or (isinstance(v, str) and len(v) <= 500))}
                    estado['rev'] += 1
                    gravar_cfg()
            a = corpo.get('audio')
            if isinstance(a, dict) and isinstance(a.get('dados'), str) and not os.path.exists(F_AUDIO):
                gravar_json(F_AUDIO, {'nome': str(a.get('nome', 'audio'))[:120], 'dados': a['dados']})
            return self.enviar(204)

        self.enviar(404, {'erro': 'não encontrado'})


if __name__ == '__main__':
    os.makedirs(DADOS, exist_ok=True)
    servidor = ThreadingHTTPServer(('0.0.0.0', PORTA), Pedido)
    servidor.daemon_threads = True
    print(f'Semáforo: servidor na porta {PORTA}, páginas em {PAGINAS}', flush=True)
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        pass

import http.server
import os
import posixpath
import urllib.parse
import sys

PORT = 8000

class NetlifyLocalHandler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        # Remove query parameters (?...) e fragmentos (#...)
        parsed_url = urllib.parse.urlparse(path)
        path_only = parsed_url.path
        
        # Primeiro, decodifica o caminho da URL
        path_only = urllib.parse.unquote(path_only)
        # Limpa o caminho
        path_only = posixpath.normpath(path_only)
        
        # Divide as partes para verificar regras específicas
        parts = path_only.strip('/').split('/')
        
        # Regras semelhantes ao netlify.toml:
        if parts and parts[0]:
            first_part = parts[0]
            # Se for um arquivo estático real com extensão (ex: .js, .css, .png, .ico), deixa seguir o fluxo normal
            _, ext = os.path.splitext(parts[-1])
            
            if not ext:
                # Se o caminho contiver "login" em qualquer lugar (evita loop infinito de redirecionamento relativo)
                if 'login' in parts:
                    return os.path.join(os.getcwd(), 'login.html')
                
                # 1. /dashboard e /dashboard/*
                if first_part == 'dashboard':
                    # Aponta para o dashboard.html físico
                    return os.path.join(os.getcwd(), 'dashboard.html')
                
                # 2. /login
                elif first_part == 'login' and len(parts) == 1:
                    return os.path.join(os.getcwd(), 'login.html')
                    
                # 3. /proposta
                elif first_part == 'proposta' and len(parts) == 1:
                    return os.path.join(os.getcwd(), 'proposta.html')
        
        # Fallback padrão do SimpleHTTPRequestHandler passando o caminho limpo (sem query params)
        return super().translate_path(path_only)

if __name__ == '__main__':
    # Adiciona suporte para UTF-8 no console se necessário
    if sys.platform.startswith('win'):
        import codecs
        try:
            sys.stdout.reconfigure(encoding='utf-8')
        except AttributeError:
            pass
            
    server_address = ('', PORT)
    httpd = http.server.HTTPServer(server_address, NetlifyLocalHandler)
    print(f"Servidor local simulando regras do Netlify rodando em http://localhost:{PORT}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServidor finalizado.")

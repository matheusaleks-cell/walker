const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 8000;

const MIME_TYPES = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.csv': 'text/csv; charset=utf-8',
};

const server = http.createServer((req, res) => {
    // Remove query parameters and fragments
    const parsedUrl = new URL(req.url, `http://${req.headers.host}`);
    let safePath = decodeURIComponent(parsedUrl.pathname);
    
    // Normalizar o caminho
    safePath = path.normalize(safePath).replace(/^(\.\.[\/\\])+/, '');
    
    const parts = safePath.split(path.sep).filter(Boolean);
    let filePath = '';

    if (parts.length > 0) {
        const firstPart = parts[0];
        const lastPart = parts[parts.length - 1];
        const ext = path.extname(lastPart);

        if (!ext) {
            // Regras semelhantes ao dev_server.py
            if (parts.includes('login')) {
                filePath = path.join(__dirname, 'login.html');
            } else if (firstPart === 'dashboard') {
                filePath = path.join(__dirname, 'dashboard.html');
            } else if (firstPart === 'login' && parts.length === 1) {
                filePath = path.join(__dirname, 'login.html');
            } else if (firstPart === 'proposta' && parts.length === 1) {
                filePath = path.join(__dirname, 'proposta.html');
            }
        }
    }

    if (!filePath) {
        // Se for a raiz, padrão para index.html
        if (safePath === '/' || safePath === '\\' || safePath === '.') {
            filePath = path.join(__dirname, 'index.html');
        } else {
            filePath = path.join(__dirname, safePath);
        }
    }

    // Tentar ler e servir o arquivo
    fs.stat(filePath, (err, stats) => {
        if (err || !stats.isFile()) {
            res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
            res.end('404 Not Found');
            return;
        }

        const ext = path.extname(filePath).toLowerCase();
        const contentType = MIME_TYPES[ext] || 'application/octet-stream';

        res.writeHead(200, { 'Content-Type': contentType });
        const stream = fs.createReadStream(filePath);
        stream.pipe(res);
    });
});

server.listen(PORT, () => {
    console.log(`Servidor local simulando regras do Netlify rodando em http://localhost:${PORT}`);
});

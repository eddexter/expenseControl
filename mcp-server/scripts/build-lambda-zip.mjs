// Empacota mcp-server como um zip pronto para `aws lambda create-function --zip-file`
// (ou `update-function-code`), usando a AWS Lambda Web Adapter como Layer — sem Docker.
//
// Passos: instala as dependências de produção numa pasta limpa (.build/) e zipa
// package.json + src/ + run.sh + node_modules em dist/function.zip. `run.sh` precisa ir
// com o bit de execução (0755) dentro do zip — por isso usamos `archiver` em vez de
// `Compress-Archive` do Windows, que não preserva permissões Unix.
import archiver from 'archiver';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const buildDir = path.join(root, '.build');
const distDir = path.join(root, 'dist');
const outPath = path.join(distDir, 'function.zip');

fs.rmSync(buildDir, { recursive: true, force: true });
fs.rmSync(distDir, { recursive: true, force: true });
fs.mkdirSync(buildDir, { recursive: true });
fs.mkdirSync(distDir, { recursive: true });

for (const file of ['package.json', 'package-lock.json', 'run.sh']) {
  fs.copyFileSync(path.join(root, file), path.join(buildDir, file));
}
fs.cpSync(path.join(root, 'src'), path.join(buildDir, 'src'), { recursive: true });

console.log('Instalando dependências de produção em .build/...');
// shell:true é necessário no Windows (npm é um .cmd, não um binário executável direto).
// Sem risco de injeção aqui: os argumentos são todos literais fixos, não vêm de input externo.
execFileSync('npm', ['ci', '--omit=dev', '--no-audit', '--no-fund'], { cwd: buildDir, stdio: 'inherit', shell: true });

console.log('Gerando dist/function.zip...');
const output = fs.createWriteStream(outPath);
const archive = archiver('zip', { zlib: { level: 9 } });

const done = new Promise((resolve, reject) => {
  output.on('close', resolve);
  archive.on('error', reject);
});
archive.on('warning', (err) => { throw err; });
archive.pipe(output);

archive.file(path.join(buildDir, 'run.sh'), { name: 'run.sh', mode: 0o755 });
archive.file(path.join(buildDir, 'package.json'), { name: 'package.json' });
archive.directory(path.join(buildDir, 'src'), 'src');
archive.directory(path.join(buildDir, 'node_modules'), 'node_modules');
await archive.finalize();
await done;

console.log(`dist/function.zip criado (${archive.pointer()} bytes).`);

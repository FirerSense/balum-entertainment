# BALUM Entertainment — versão funcional

## 1. Criar o backend
1. Crie um projeto no Supabase.
2. No SQL Editor, execute `supabase.sql`.
3. Em Authentication > Providers, habilite Google.
4. Configure as URLs de redirecionamento do Google/Supabase para o endereço onde o site ficará hospedado.
5. Crie um bucket PRIVADO chamado `event-media`.
6. No `index.html`, substitua:
   - `COLE_SUA_SUPABASE_URL`
   - `COLE_SUA_SUPABASE_ANON_KEY`

## 2. Tornar uma conta administradora
Depois de entrar uma vez com a conta que será da BALUM, execute no SQL Editor:

update public.profiles
set is_admin = true
where email = 'SEU_EMAIL_ADMIN';

Não há clientes, e-mails, pastas ou eventos fictícios no projeto.

## 3. Importante sobre upload
A estrutura de banco já está pronta para álbuns e arquivos. O próximo passo de produção é ligar a tela administrativa ao Storage privado para upload e exclusão de fotos/vídeos. O front-end atual já usa URLs assinadas para visualizar os arquivos cadastrados.

## 4. Publicar
Pode hospedar o `index.html` em Vercel, Netlify, Cloudflare Pages ou outro serviço de hospedagem estática.

## 5. Segurança
Nunca coloque a `service_role key` do Supabase no HTML. No navegador use somente a chave `anon`.

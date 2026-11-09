# ARVION LAB: CEO TYCOON

*Um prédio. Mil funcionários. Apenas um CEO.*

## Configurar (5 min)
1. Crie um projeto em supabase.com.
2. SQL Editor → cole e rode `schema.sql`.
3. Database → Extensions → ative `pg_cron` e rode a última linha comentada do `schema.sql` (sorteio a cada minuto).
4. Project Settings → API: copie **URL** e **anon key** para o topo do script em `index.html`.

## Executar local
`npx serve .` (ou `python3 -m http.server`) e abra em duas abas/navegadores com @ diferentes.

## Publicar
Suba a pasta na Netlify, Vercel ou GitHub Pages (site estático, sem build). Divulgue o link.

## Como a regra funciona
- Todas as mudanças passam por funções no banco (`security definer`); o navegador não escreve direto nas tabelas.
- `run_draw()` roda só no servidor: por vaga aberta, sorteia entre candidatos elegíveis com `order by random()` (1/N para cada um), com lock para impedir vaga duplicada.
- Perdedores precisam pedir promoção de novo.

## Checklist de teste
Dois navegadores → ambos veem os personagens → peça promoção nos dois → aguarde o sorteio (ou rode `select run_draw();` no SQL Editor) → promoção aparece nos dois → recarregue e confirme a persistência.

## Limites desta v1
- @ é só identificador de exibição; a sessão fica no `localStorage` (limpar o navegador perde o acesso ao personagem).
- Requisitos de promoção: desempenho ≥ cargo×25 e cansaço ≤ 80 (ajuste em `request_promotion`).

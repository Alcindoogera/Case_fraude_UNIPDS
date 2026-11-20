--Projeto ABTFRAUDE: Treinar um modelo para prevenir Fraudes
-- O PROJETO: Reunir "tudo" numa tabela, que servirá para modelagem e analise dos dados!!


--Tabelas Fornecidas:
-- 1. categorias: `unipdsaula-513209.ABTFRAUDE.categorias`
-- 2. comportamentais: `unipdsaula-513209.ABTFRAUDE.comportamentais`
-- 3. financeiros: `unipdsaula-513209.ABTFRAUDE.financeiros`
-- 4. modelo: `unipdsaula-513209.ABTFRAUDE.modelo`
-- 5. paises: `unipdsaula-513209.ABTFRAUDE.paises`
-- 6. transacoes: `unipdsaula-513209.ABTFRAUDE.transacoes`

-- Colunas nas tabelas:
-- 1.categorias: id_categoria | departamento | nivel_risco_categoria | requer_doc_adicional | ativo
-- 2.comportamentais: id_transacao | score_1 | score_2 | score_4 | score_7 | dt_calculo_score | versao_modelo_comportamental |
-- 3.finaceiros: id_transação | scor_3 | score_6 | score_9 | score_10 | moeda_calculo | recalculado |
-- 4.modelo: id_transacao | score_8 | score_fraude_modelo | experimento | thresehold_transacao |
-- 5. paises: sigla_pais | nome_pais | regiao | moeda_local | locale | ativo |
-- 6. transacoes: id_transacao | data_compra | valor_compra | pais | produto | categoria_produto | entrega_doc_1 | entrega_doc_2 | entrega_doc_3 | canal_venda | is_teste | versao_api |



-- Parte 1: Construção da abt_fraude
-- Critério de aceite: 150.000 transações
-- QUERY principal
-- fazer um INNER JOIN(ou somente JOIN) entre tabelas, pois queremos retornar apenas as transações onde temos registros em todas as outras tabelas

CREATE TABLE `unipdsaula-513209.ABTFRAUDE`.abt_fraude AS (
  SELECT
  t.entrega_doc_1,
  t.entrega_doc_2,
  t.entrega_doc_3,
  t.data_compra,
  t.valor_compra,
  t.pais,
  t.produto,
  t.categoria_produto,
  mo.score_8,
  mo.score_fraude_modelo,
  mo.fraude,
  cb.score_1,
  cb.score_2,
  cb.score_4,
  cb.score_5,
  cb.score_7,
  fi.score_3,
  fi.score_6,
  fi.score_9,
  fi.score_10,

FROM `unipdsaula-513209.ABTFRAUDE.transacoes` t
JOIN `unipdsaula-513209.ABTFRAUDE.comportamentais` cb
ON cb.id_transacao = t.id_transacao
JOIN `unipdsaula-513209.ABTFRAUDE.financeiros` fi
ON fi.id_transacao = t.id_transacao
JOIN `unipdsaula-513209.ABTFRAUDE.modelo` mo
ON mo.id_transacao = t.id_transacao
-- no primeiro RUN encontramos 150.200 transações, ou seja 200 a mais que o aceite
-- a hipótese é que estas 200 transações a mais sejam testes de fraude, então vamos utilizar os registros  "is_teste" na tabela "transacoes" -- 
WHERE t.is_teste = 0
-- agora sim são 150.000 registros (200 são testes)
)

--Parte 2: Tomada de decisões

--- CONTEXTO
--Agora a liderança de risco chega com um pedido aberto: eles precisam decidir onde investir no próximo trimestre – apertar regras, treinar um novo modelo, colocar revisão manual em algum segmento? – e querem que você diga onde está o problema

-- Vamos gerar algumas recomendações no final do exercício
-- Vamos utilizar como base a tabela `unipdsaula-513209.ABTFRAUDE.abt_fraude` criada na parte 1

--1. PANORAMA: Tamanho do problema
-- antes de recortar por segmento, precimos de linha de base, quão grande o problema é, em número e em valor?

SELECT
  COUNT(*)                                                         AS total,
  SUM(fraude)                                                      AS fraudes,
  ROUND(100.0*AVG(fraude), 3)                                      AS taxa_fraude_pct,
  ROUND(SUM(CASE WHEN fraude = 1 THEN valor_compra ELSE 0 END), 2) AS valor_exposto,
  ROUND(AVG(CASE WHEN fraude = 1 THEN valor_compra END), 2)        AS ticket_medio_fraude,
  ROUND(AVG(valor_compra), 2)                                      AS ticket_medio_geral
FROM `unipdsaula-513209.ABTFRAUDE.abt_fraude`;
-- resultado da QUERY:
-- Percentagem fraude= 5% | Valor exposto: aprox: KR$ 550 | ticket médio Fraude ; R$ 73,00 | tocket médio geral: R$ 43,52


/* ---------------------------------------------------------------
2) FRAUDE POR PAÍS (JOIN com dimensão + piso de volume)
O primeiro recorte natural: o risco é o mesmo em todo lugar ou tem geografia?
O HAVING descarta praças pequenas demais para uma taxa confiável.
--------------------------------------------------------------- */

SELECT
  p.nome_pais,
  p.regiao,
  COUNT(*)                      AS transacoes,
  ROUND(100.0*AVG(a.fraude), 2) AS taxa_fraude_pct
FROM `unipdsaula-513209.ABTFRAUDE.abt_fraude` a
JOIN `unipdsaula-513209.ABTFRAUDE.paises` p ON p.sigla_pais = a.pais
GROUP BY p.nome_pais, p.regiao
HAVING COUNT(*) >= 1000
ORDER BY taxa_fraude_pct DESC;
 -- Resultado da Query:
 -- Percentual Fraudes:Brasil; 5,52% | Argentina: 3,69% | Estados Unidos: 3,08% | Uruguai: 0,98%
 -- Volume transações: Brasil: 111.628 | Argentina: 31.964 | Estados Unidos: 2273 | Uruguai: 2967
 
 -- Calibrar as Ações por País.

 /* ----------------------------------------------------------------------
   3. RISCO CADASTRADO vs. REALIDADE  (JOIN com dim_categorias)
   A empresa classificou as categorias como risco baixo/médio/alto. Antes de
   confiar nessa etiqueta para tomar decisão, precisamos testar se ela bate com
   a fraude observada
   ---------------------------------------------------------------------- */
SELECT
    c.nivel_risco_categoria,
    COUNT(*)                            AS transacoes,
    ROUND(100.0*AVG(a.fraude), 2)       AS taxa_fraude_pct
FROM `unipdsaula-513209.ABTFRAUDE.abt_fraude`  a
JOIN `unipdsaula-513209.ABTFRAUDE.categorias`  c ON c.id_categoria = a.categoria_produto
GROUP BY c.nivel_risco_categoria
ORDER BY taxa_fraude_pct DESC;

--Resultado da QUERY:
-- percentagem fraude: risco alto: 5,06% | Risco médio: 5,21% | risco baixo: 4,74%
-- observe que risco alto tem % menor que risco médio, ou seja Modelo não está calibrado


/* ---------------------------------------------------------------
   4) FRAUDE POR FAIXA DE VALOR  (CASE WHEN)
   Transforma o valor contínuo em faixas comparáveis.
--------------------------------------------------------------- */
SELECT
    CASE
        WHEN valor_compra < 100 THEN '1) ate 100'
        WHEN valor_compra < 500 THEN '2) 100-500'
        ELSE                         '3) acima de 500'
    END                              AS faixa_valor,
    COUNT(*)                         AS transacoes,
    ROUND(100.0*AVG(fraude), 2)      AS taxa_fraude_pct
FROM `unipdsaula-513209.ABTFRAUDE.abt_fraude`
GROUP BY faixa_valor
ORDER BY faixa_valor;

/* Resultado da query
  até R$ 100,00            taxa de fraude = 4,6% | # fraudes = 6313 | 84% das fraudes 
  de R$ 100,0 a R$ 500,00 taxa de fraude = 8,84% | # fraudes = 1032 | 13,8% das fraudes 
  acima de R$ 500,00    taxa de fraude = 14,95%  | # fraudes = 155  | 2,1% das fraudes 

  Concluindo que taxa de fraude sobe acentuadamemte conforme sobe o ticket médio 
  A próxima dúvida é quanto perdemos R$, em cada faixa ? */

  -- Comparando taxa de fraude e onde está o dinheiro por faixa

WITH base AS (
  SELECT
    CASE
      WHEN valor_compra < 100  THEN '1) ate 100'
      WHEN valor_compra < 500  THEN '2) 100-500'
      WHEN valor_compra >= 500 THEN '3) acima de 500'
      ELSE                          '4) valor NULL'  -- separa nulos em vez de escondê-los na faixa 3
    END AS faixa_valor,
    fraude,
    valor_compra
  FROM `unipdsaula-513209.ABTFRAUDE.abt_fraude`
)

  SELECT
  faixa_valor,
  COUNT(*)      AS transacoes,
  SUM(fraude)   AS fraudes,
  ROUND(100.0 * SUM(fraude) / COUNT(*), 2) AS taxa_fraude_pct,
  ROUND(100.0 * SUM(fraude) / SUM(SUM(fraude)) OVER (), 1) AS pct_dos_casos, -- % das fraudes daquela faixa sobre o total de fraudes.
  ROUND(SUM(CASE WHEN fraude = 1 THEN valor_compra ELSE 0 END), 2) AS valor_exposto,
  ROUND(100.0 * SUM(CASE WHEN fraude = 1 THEN valor_compra ELSE 0 END)
        / SUM(SUM(CASE WHEN fraude = 1 THEN valor_compra ELSE 0 END)) OVER (), 1)  AS pct_do_valor,
  ROUND(SAFE_DIVIDE(
        SUM(CASE WHEN fraude = 1 THEN valor_compra ELSE 0 END),
        SUM(fraude)
      ), 2)  AS perda_media_por_fraude
FROM base
GROUP BY faixa_valor
ORDER BY faixa_valor;

/* 
            até R$ 100,00 taxa de fraude = 4,6%  | valor exposto: KR$ 169
  de R$ 100,0 a R$ 500,00 taxa de fraude = 8,84% | valor exposto: KR$ 233 
       acima de R$ 500,00 taxa de fraude = 14,95%| valor exposto: KR$ 144

Sugestão: Formular poítica de detecção de fraude mais restritiva na categoria entre 100-500
*/


/* ------------------------------------------------------------------
   5) O SCORE DO MODELO SEPARA FRAUDE?  (NTILE - função de janela)
   Divide a base em 10 faixas iguais por score e mede a taxa em cada uma.
   Espera-se que a taxa cresça de forma consistente do decil 1 ao 10.
   ------------------------------------------------------------------ */
WITH faixas AS (
    SELECT
        fraude,
        NTILE(10) OVER (ORDER BY score_fraude_modelo) AS decil
    FROM `unipdsaula-513209.ABTFRAUDE.abt_fraude`
)
SELECT
    decil,
    COUNT(*)                        AS transacoes,
    ROUND(100.0*AVG(fraude), 2)     AS taxa_fraude_pct
FROM faixas
GROUP BY decil
ORDER BY decil;

-- 1:2,77  2:4,59  3:3,33  4:0,31  5:0,62  6:1,27  7:2,05  8:5,10  9:8,63  10:21,33
-- Leitura: separa bem só no topo (decil 10 ~= 4x a base); o meio não é monotônico.
/*
conclusão: o modelo não está bom, pois as classes 1 a 10, possuem faixas muito distintas< ex: faixa 4 = 0,31 e faixa 10 = 21,33, deve-se recalibrar/retreinar  o modelo
*/



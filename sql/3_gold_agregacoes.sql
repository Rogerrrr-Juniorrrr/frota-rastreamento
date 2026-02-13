-------------------------------------------------------------
------------------AGREGAÇÃO PERFIL CARTEIRA------------------
-------------------------------------------------------------

CREATE OR REPLACE TABLE tr_gold.agg_perfil_carteira AS
SELECT
  -- Agrupamento Temporal
  FORMAT_DATE('%Y-%m', f.data_contrato) AS mes_referencia,
  
  -- Segmentação de Negócio
  da.UF AS uf,          -- Geografia
  dv.linha_veiculo,      -- LEVES, PESADOS, MOTOS
  
  -- Métricas
  COUNT(DISTINCT f.id_instalacao) AS total_contratos,
  COUNTIF(f.status_contrato IN ('ATIVO', 'ATIVO IRREGULAR')) AS contratos_ativos,
  COUNTIF(f.status_contrato = 'INATIVO') AS contratos_cancelados,
  
  -- Valor Financeiro (Soma da FIPE dos veículos protegidos)
  -- Isso mostra o "Tamanho do Risco/Carteira"
  SUM(dv.valor_fipe) AS valor_total_fipe_protegido

FROM tr_silver.fct_instalacoes f
LEFT JOIN tr_silver.dim_veiculos dv
  ON f.id_veiculo = dv.id_veiculo
LEFT JOIN tr_silver.dim_associados da
  ON f.id_associado = da.id_associado
  
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2, 5 DESC;



-------------------------------------------------------------
------------------AGREGAÇÃO STATUS OPERAÇÃO------------------
-------------------------------------------------------------

CREATE OR REPLACE TABLE tr_gold.agg_status_operacao AS
SELECT
  -- Agrupamento ÚNICO por Estado (1 linha por UF)
  f.uf_entrega,

  -- 1. EM TRÂNSITO (Saiu da base, mas não chegou no técnico)
  COUNTIF(f.status_envio = 'ENVIADO' AND f.status_instalacao = 'PENDENTE') AS qtd_em_transito,

  -- 2. GARGALO DE INSTALAÇÃO (Já chegou, mas o técnico não instalou)
  -- Esse é o número mais importante para você cobrar agilidade!
  COUNTIF(f.status_envio = 'ENTREGUE' AND f.status_instalacao = 'PENDENTE') AS qtd_estoque_parado,

  -- 3. INSTALADOS (Sucesso Operacional)
  COUNTIF(f.status_instalacao = 'INSTALADO') AS qtd_instalados,

  -- 4. RISCO DE COMPLIANCE (Instalou, mas não assinou o termo)
  COUNTIF(f.status_instalacao = 'INSTALADO' AND f.termo_assinado = 'NÃO') AS qtd_risco_termo,
  
  -- Total Geral
  COUNT(*) AS total_veiculos

FROM tr_silver.fct_instalacoes f
WHERE f.status_contrato = 'ATIVO' AND uf_entrega IS NOT NULL -- Olhamos apenas a carteira ativa
GROUP BY 1
ORDER BY 4 DESC; -- Ordenado pelos estados com mais instalações




-------------------------------------------------------------
-----------------AGREGAÇÃO RANKING PARCEIROS-----------------
-------------------------------------------------------------


CREATE OR REPLACE TABLE tr_gold.agg_ranking_parceiros AS
SELECT
  -- Dimensão Parceiro
  COALESCE(di.nome_instalador, 'PARCEIRO NÃO VINCULADO') AS nome_instalador,
  di.cidade_base,
  di.uf,
  di.empresa_credenciada, -- AZIMUTE ou NULL

  -- KPIs de Volume
  COUNT(DISTINCT f.id_instalacao) AS total_ordens_servico,
  
  -- KPIs de Status (Quantos ele concluiu vs deixou pendente)
  COUNTIF(f.status_instalacao = 'INSTALADO') AS qtd_instalados,
  COUNTIF(f.status_instalacao = 'PENDENTE' 
          AND f.status_envio = 'ENTREGUE' 
          AND f.status_contrato IN ('ATIVO', 'ATIVO IRREGULAR')) AS qtd_pendentes,
  COUNTIF(f.status_instalacao = 'REMOVIDO') AS qtd_removidos,
  
  -- KPI Financeiro (Volume de Repasse)
  -- Importante para saber o tamanho da parceria $$$
  SUM(f.valor_instalacao) AS valor_total_repassado,
  
  -- KPI de Eficiência (Status de Envio e Média de dias entre Envio e Entrega)
  COUNTIF(f.status_envio = 'ENVIADO' AND f.status_instalacao = 'PENDENTE') AS qtd_em_transito,
  COUNTIF(f.status_envio IN ('N/A', 'ENTREGUE')) AS qtd_entregues,

  -- Só calcula se tiver as duas datas preenchidas
  ROUND(AVG(DATE_DIFF(f.data_entrega, f.data_envio, DAY)), 1) AS media_dias_transporte,
  ROUND(AVG(DATE_DIFF(f.data_instalacao, f.data_entrega, DAY)), 1) AS media_dias_instalacao


FROM tr_silver.fct_instalacoes f
LEFT JOIN tr_silver.dim_instaladores di
  ON f.id_instalador = di.id_instalador

WHERE f.id_instalador IS NOT NULL -- Ignora instalações sem técnico vinculado
  AND f.status_envio != 'PENDENTE' -- Ignora envios pendentes
  AND f.status_instalacao != 'JÁ POSSUI' -- Ignora que já possui rastreador
GROUP BY 1, 2, 3, 4
ORDER BY 6 DESC; -- Ordena por quem tem mais ordens de serviço





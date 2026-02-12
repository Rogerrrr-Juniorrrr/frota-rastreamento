--------------------------------------------------------------
-----------------------FATO INSTALACOES-----------------------
--------------------------------------------------------------


CREATE OR REPLACE TABLE tr_silver.fct_instalacoes AS

  WITH ref_associados AS(
    SELECT  
      -- PK da Fato
      TO_HEX(MD5(CONCAT(REPLACE(UPPER(TRIM(placa)), '-', ''), TO_HEX(MD5(TRIM(REGEXP_REPLACE(cpf, r'[^0-9]', ''))))))) AS id_instalacao,
      -- FKs
      TO_HEX(MD5(TRIM(REGEXP_REPLACE(cpf, r'[^0-9]', '')))) AS id_associado,

      TO_HEX(MD5(REPLACE(UPPER(TRIM(placa)), '-', ''))) AS id_veiculo_ra, -- Necessário para o Join
      
      -- Dados
      PARSE_DATE('%d/%m/%Y', dt_contrato) AS data_contrato,
      UPPER(TRIM(situacao)) AS status_contrato,
      
      ingested_at -- Necessário para o QUALIFY abaixo

    FROM tr_bronze.associados
    QUALIFY ROW_NUMBER() OVER(PARTITION BY placa ORDER BY ingested_at DESC) = 1 -- Para deduplicação
  ),
  ref_base_frota AS (
    SELECT
      -- Criando as FK's
      TO_HEX(MD5(REGEXP_REPLACE(CAST(imei_aparelho AS STRING), r'[^0-9]', ''))) AS id_dispositivo,
      
      TO_HEX(MD5(REPLACE(UPPER(TRIM(placa)), '-', ''))) AS id_veiculo_rbf, -- Necessário para o Join

      -- FK Técnico/Auto Elétrica Disponível (Nome + Cidade = compatibilidade com a PK de dim_instaladores)
      TO_HEX(MD5(CONCAT(UPPER(TRIM(auto_eletrica_compativel)), UPPER(TRIM(cidade))))) AS id_instalador,

      -- Limpeza do valor de instalação
      SAFE_CAST(
          REPLACE(REPLACE(REPLACE(valor_instalacao, 'R$', ''), '.', ''), ',', '.') 
        AS NUMERIC) AS valor_instalacao,

        -- DADOS OPERACIONAIS (Adicionados)
      PARSE_DATE('%d/%m/%Y', dt_envio) AS data_envio,
      PARSE_DATE('%d/%m/%Y', dt_entrega) AS data_entrega,
      UPPER(TRIM(status_envio)) AS status_envio,       -- Ex: ENTREGUE, ENVIADO, PENDENTE
      UPPER(TRIM(status_instalacao)) AS status_instalacao, -- Ex: INSTALADO, PENDENTE
      UPPER(TRIM(termo_assinado)) AS termo_assinado,   -- Ex: SIM, NÃO


      -- DADOS LOGÍSTICOS
      INITCAP(TRIM(cidade)) AS cidade_operacao,
      UPPER(TRIM(uf)) AS uf_operacao,

      ingested_at -- Necessário para o QUALIFY abaixo

    FROM tr_bronze.base_frota
    QUALIFY ROW_NUMBER() OVER(PARTITION BY placa ORDER BY ingested_at DESC) = 1  -- Para deduplicação
  )

  SELECT 
    ra.id_instalacao, -- PK
    ra.id_associado, -- FK (associado)
    ra.id_veiculo_ra AS id_veiculo, -- FK (veiculo)
    rbf.id_dispositivo, -- FK (dispositivo)
    rbf.id_instalador, -- FK (Técnico/Auto Elétrica)
    
    -- Contrato & Financeiro
    ra.data_contrato,
    ra.status_contrato,
    -- Se for PESADOS, pega o preço de pesados do instalador. Senão, pega o padrão (leves).
    CASE 
      WHEN dv.linha_veiculo = 'PESADOS' THEN di.preco_pesados
      ELSE di.preco_padrao
    END AS valor_instalacao,
    
    -- Operação e Logística
    rbf.data_envio,
    rbf.data_entrega,
    rbf.status_envio,
    rbf.status_instalacao,
    rbf.termo_assinado,
    
    -- Tenta pegar do cadastro do técnico (di). Se for NULL, pega da operação (rbf).
    COALESCE(di.cidade_base, rbf.cidade_operacao) AS cidade_entrega, 
    COALESCE(di.uf, rbf.uf_operacao) AS uf_entrega,

    -- Auditoria
    ra.ingested_at

  FROM ref_associados ra -- CTE ref_associados
  
  -- Join com Frota (Conectando as CTEs)
  LEFT JOIN ref_base_frota rbf -- CTE ref_base_frota
    ON rbf.id_veiculo_rbf = ra.id_veiculo_ra -- Junção da CTE ref_associados com CTE ref_base_frotas

  -- Join CTE Associados com Veículos (para saber a LINHA: Pesado ou Leve)
  LEFT JOIN tr_silver.dim_veiculos dv
    ON dv.id_veiculo = ra.id_veiculo_ra

  -- Join CTE Frota com Instaladores (para buscar a TABELA DE PREÇOS)
  LEFT JOIN tr_silver.dim_instaladores di
    ON di.id_instalador = rbf.id_instalador;



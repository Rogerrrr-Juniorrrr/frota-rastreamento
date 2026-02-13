-------------------------------------------------------------
--------------------DIMENSÃO INSTALADORES--------------------
-------------------------------------------------------------

CREATE OR REPLACE TABLE tr_silver.dim_instaladores AS
  SELECT
    -- Hash do Nome + Cidade (Criando ID)
    TO_HEX(MD5(UPPER(TRIM(instalador)))) AS id_instalador,
    
    UPPER(TRIM(instalador)) AS nome_instalador,
    INITCAP(TRIM(cidade)) AS cidade_base,
    UPPER(TRIM(uf)) AS uf,
    
    REGEXP_REPLACE(telefone, r'[^0-9]', '') AS contato,
    
    -- Flags de Capacidade
    IF(UPPER(TRIM(atende_pesados)) = 'SIM', TRUE, FALSE) AS atende_pesados,
    
    -- Valores da instalação: convertendo "R$ 90,00" para 90.00
    SAFE_CAST(
      REPLACE(REPLACE(REPLACE(valor_leves, 'R$', ''), '.', ''), ',', '.') 
    AS NUMERIC) AS preco_padrao,

    SAFE_CAST(
      REPLACE(REPLACE(REPLACE(valor_pesados, 'R$', ''), '.', ''), ',', '.') 
    AS NUMERIC) AS preco_pesados,

    -- Se for SIM, grava 'AZIMUTE'. Se não, deixa NULL (espaço para outros parceiros futuros)
    IF(UPPER(TRIM(parceiro_azimute)) = 'SIM', 'AZIMUTE', NULL) AS empresa_credenciada,
    
    CURRENT_TIMESTAMP() AS processed_at

  FROM tr_bronze.instaladores
  WHERE instalador IS NOT NULL
QUALIFY ROW_NUMBER() OVER(PARTITION BY nome_instalador, cidade_base ORDER BY instalador) = 1;


-------------------------------------------------------------
---------------------DIMENSÃO ASSOCIADOS---------------------
-------------------------------------------------------------

CREATE OR REPLACE TABLE tr_silver.dim_associados AS
  SELECT 
    -- Hash do CPF (criando ID)
    TO_HEX(MD5(TRIM(REGEXP_REPLACE(cpf, r'[^0-9]', '')))) AS id_associado,

    -- LIMPEZA DE CARACTERES ESPECIAIS E FORMATAÇÃO DO NOME DOS ASSOCIADOS
    INITCAP(TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(associado, r'[^a-zA-ZÀ-ÿ ]', ''),r'\s+', ' ' ))) AS nome_associado,
    
    -- LIMPEZA E FORMATAÇÃO DO CPF DOS ASSOCIADOS
    TRIM(REGEXP_REPLACE(cpf, r'[^0-9]', '')) AS cpf,
    
    -- CONVERSÃO DE TEXTO DD/MM/YYYY -> DATA
    PARSE_DATE('%d/%m/%Y', dt_nascimento) AS dt_nascimento,
    
    -- LIMPEZA E FORMATAÇÃO DO TELEFONE DOS ASSOCIADOS
    TRIM(REGEXP_REPLACE(telefone, r'[^0-9]', '')) AS telefone,
    
    LOWER(TRIM(email)) AS email,
    UPPER(TRIM(estado)) AS UF,
    INITCAP(TRIM(cidade)) AS cidade,

    -- Metadado de Processamento
    CURRENT_TIMESTAMP() AS processed_at
    
  FROM tr_bronze.associados

  QUALIFY ROW_NUMBER() OVER(PARTITION BY cpf ORDER BY ingested_at DESC) = 1;



-------------------------------------------------------------
---------------------DIMENSÃO VEICULOS---------------------
-------------------------------------------------------------

CREATE OR REPLACE TABLE tr_silver.dim_veiculos AS(
  SELECT
    -- PK: Hash da PLACA (Criando ID)
    TO_HEX(MD5(REPLACE(UPPER(TRIM(placa)), '-', ''))) AS id_veiculo,

    -- Dados Identificadores Limpos
    REPLACE(UPPER(TRIM(placa)), '-', '') AS placa,
    REGEXP_REPLACE(UPPER(TRIM(chassi)), r'[^0-9a-zA-Z]', '') AS chassi,

    -- Inteligência de Marca
    COALESCE(
      -- Se a marca original é confiável, usa ela
      IF(UPPER(TRIM(a.marca)) NOT IN ('OUTROS', 'IMP/OUTROS'), UPPER(TRIM(a.marca)), NULL),
      -- Se não, tenta a do dicionário
      rm.marca_normalizada,
      -- Fallback
      'OUTROS') AS marca,

    -- Modelo Limpo para Leitura
    UPPER(TRIM(REPLACE(REPLACE(modelo, '-', ' '), '.', ' '))) AS modelo,   
    
    -- Dados Numéricos Seguros
    ano_de_fabricacao AS ano_fabricacao,

    SAFE_CAST(
      REPLACE(REPLACE(REPLACE(a.valor_fipe, 'R$', ''), '.', ''), ',', '.') 
    AS NUMERIC) AS valor_fipe,
  
    -- Padronização de Categoria
    CASE
      WHEN UPPER(TRIM(linha)) IN ('CAMINHÃO', 'TERCEIROS', 'MAQUINAS') THEN 'PESADOS'

      WHEN UPPER(TRIM(linha)) IN ('PARTICULAR') THEN 'LEVES'

      WHEN UPPER(TRIM(linha)) IN ('GUINDASTE HID VEIC MD 45007') THEN 'CARRETAS'

      ELSE UPPER(TRIM(linha)) 
    
    END AS linha_veiculo,

    -- Metadado
    CURRENT_TIMESTAMP() AS processed_at

  FROM `tr_bronze.associados` a
  -- Conectando as marcas de dim_veiculos com o dicionário ref_marcas  
  LEFT JOIN (SELECT palavra_chave, REPLACE(marca_normalizada, '-', ' ') AS marca_normalizada FROM `tr_bronze.ref_marcas`) rm
  ON REGEXP_REPLACE(UPPER(a.modelo), r'[^a-zA-Z0-9]', '') 
      LIKE CONCAT('%', REGEXP_REPLACE(UPPER(rm.palavra_chave), r'[^a-zA-Z0-9]', ''), '%')
  WHERE placa IS NOT NULL

  QUALIFY ROW_NUMBER() OVER(PARTITION BY cpf ORDER BY ingested_at DESC) = 1
);



-------------------------------------------------------------
--------------------DIMENSÃO DISPOSITIVOS--------------------
-------------------------------------------------------------

CREATE OR REPLACE TABLE tr_silver.dim_dispositivos AS 
  SELECT
    -- Hash do IMEI (Criando ID)
    TO_HEX(MD5(REGEXP_REPLACE(CAST(imei_aparelho AS STRING), r'[^0-9]', ''))) AS id_dispositivo,

    -- O IMEI visível
    REGEXP_REPLACE(CAST(imei_aparelho AS STRING), r'[^0-9]', '') AS imei,

    -- Empresa fornecedora
    UPPER(TRIM(empresa_rastreamento)) AS empresa,

    -- Quando vimos este IMEI pela primeira vez na base?
    MIN(ingested_at) OVER(PARTITION BY REGEXP_REPLACE(CAST(imei_aparelho AS STRING), r'[^0-9]', '')) AS data_primeira_aparicao,

    CURRENT_TIMESTAMP() AS processed_at

  FROM tr_bronze.base_frota
  WHERE imei_aparelho IS NOT NULL AND imei_aparelho != ''

  -- Deduplicação: Garante 1 linha por IMEI (pela última atualização de fabricante)
  QUALIFY ROW_NUMBER() OVER(PARTITION BY imei ORDER BY ingested_at DESC) = 1;

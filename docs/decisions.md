# Registro de decisões

> Decisões de desenho do Cadastro Feliz, com os motivos. Uma mudança em qualquer item deve ser registrada aqui.

**Origem:** *definida* foi escolhida pelo responsável do projeto; *proposta* veio do desenho e pode ser revista.

| # | Decisão | Origem |
|---|---|---|
| [1](#1-transactional-outbox-em-vez-de-publicar-direto-na-fila) | Transactional Outbox em vez de publicar direto na fila | Definida |
| [2](#2-banco-e-schema-únicos) | Banco e schema únicos | Definida |
| [3](#3-e-mail-repetido-retorna-409) | E-mail repetido retorna 409 | Definida |
| [4](#4-bloqueio-de-15-minutos-em-janela-fixa) | Bloqueio de 15 minutos em janela fixa | Definida |
| [5](#5-redis-comum-para-o-contador-de-tentativas) | Redis comum para o contador de tentativas | Definida |
| [6](#6-uma-stack-ativa-por-vez) | Uma stack ativa por vez | Proposta |
| [7](#7-rota-post-users-sem-prefixo) | Rota `POST /users` sem prefixo | Proposta |
| [8](#8-redis-limiter-indisponível-retorna-500) | `redis-limiter` indisponível retorna 500 | Proposta |
| [9](#9-retentativas-controladas-pelo-banco) | Retentativas controladas pelo banco | Proposta |
| [10](#10-fila-transporta-só-o-identificador-do-evento) | Fila transporta só o identificador do evento | Proposta |
| [11](#11-mailpit-como-caixa-de-e-mail) | Mailpit como caixa de e-mail | Proposta |
| [12](#12-navegador-chama-a-api-diretamente) | Navegador chama a API diretamente | Proposta |
| [13](#13-escopo-das-convenções-do-agentsmd) | Escopo das convenções do `AGENTS.md` | Proposta |
| [14](#14-forma-única-das-respostas-de-erro) | Forma única das respostas de erro | Definida |

## 1. Transactional Outbox em vez de publicar direto na fila

Publicar na fila durante a requisição cria duas escritas sem transação comum, e uma delas pode falhar sem a outra. Com o outbox, usuário e evento são gravados de forma atômica. O custo é ter um relay e aceitar entrega *at-least-once*, com possíveis e-mails duplicados.

## 2. Banco e schema únicos

Um único schema, com migrations em SQL puro aplicadas pelo container `migrate`, garante que as três stacks sejam realmente comparáveis e intercambiáveis. Além disso, permite demonstrar uma stack assumindo eventos deixados por outra.

**Custo:** nenhuma stack usa a ferramenta de migrations do próprio framework.

## 3. E-mail repetido retorna 409

É o status mais preciso para conflito com um recurso existente, e separa esse caso dos erros de validação (422). Amplia a lista inicial de status (201, 422, 429, 500).

**Custo:** o status revela que o e-mail já está cadastrado.

## 4. Bloqueio de 15 minutos em janela fixa

Depois de 5 tentativas com o mesmo e-mail, a API responde 429 sem consultar o banco, o que reduz a carga causada por tentativas repetidas. A duração limita também o dano de um terceiro bloquear o e-mail de outra pessoa.

**Custo:** a janela fixa é simples, mas permite uma rajada na virada da janela.

## 5. Redis comum para o contador de tentativas

O contador fica em um container compartilhado, o `redis-limiter`. Laravel e NestJS mantêm um `redis` próprio só para a fila, e a stack Go não tem Redis próprio.

**Substitui** o desenho anterior, com um Redis por stack, em que a stack Go tinha um Redis só para o contador.

**Motivos**
- **Regra comum:** o limite de tentativas pertence ao cadastro, como o banco. A fila é um detalhe de cada stack.
- **Limite consistente:** um e-mail bloqueado continua bloqueado ao trocar de stack.
- **Cadastro independente da fila:** no desenho anterior, uma queda do Redis em Laravel e NestJS derrubava o cadastro junto com a fila.
- **Configurações opostas:** a fila precisa de `noeviction`, e o BullMQ a exige. O contador é descartável e não precisa de persistência.

**Alternativas descartadas**
- **Um Redis comum para tudo:** economiza containers, mas mistura fila e contador e faz uma queda do Redis parar o cadastro.
- **Contador em memória:** zeraria a cada reinício e não funcionaria com réplicas.
- **Contador no Postgres:** contrariaria o objetivo de não carregar o banco.

**Custos**
- Laravel e NestJS têm dois Redis e duas conexões para configurar.
- Chave e script passam a ser um contrato entre as stacks, definido em [api-contract.md](api-contract.md#operação-no-redis).
- Testes do 429 precisam de outro e-mail ou de `make reset-limits`, porque o contador sobrevive à troca de stack.

## 6. Uma stack ativa por vez

O frontend usa sempre o mesmo endereço, então as três APIs publicam a porta 8080. `make up-<stack>` derruba as demais antes de subir a escolhida.

**Alternativa descartada:** um gateway à frente das APIs permitiria stacks simultâneas, mas acrescenta um componente que o caso de uso não exige.

## 7. Rota `POST /users` sem prefixo

Segue a especificação do projeto. O `AGENTS.md` sugere `/api/v1`, mas essa orientação vem de outro produto (ver decisão 13). Com um único endpoint, o versionamento ainda não traz benefício.

## 8. `redis-limiter` indisponível retorna 500

Se o contador estiver fora do ar, a API não consegue aplicar o limite. Retornar 500 é coerente com a regra de responder 500 em indisponibilidades e evita que uma falha do Redis jogue toda a carga no banco.

**Custo:** o `redis-limiter` é ponto único de falha do cadastro nas três stacks. Em produção, ele precisaria de alta disponibilidade.

## 9. Retentativas controladas pelo banco

Cada fila tem um mecanismo próprio de retentativa, com comportamentos diferentes. Com `attempts` e `available_at` na tabela, as três stacks seguem exatamente a mesma regra, e o estado de cada evento pode ser consultado com SQL.

## 10. Fila transporta só o identificador do evento

O PostgreSQL continua sendo a única fonte da verdade, e dados pessoais não passam pelo Redis nem pelo RabbitMQ.

**Custo:** o worker faz uma consulta a mais para cada mensagem.

## 11. Mailpit como caixa de e-mail

Captura os e-mails de todas as stacks em um só lugar, sem enviá-los de verdade, e oferece interface web. Usa SMTP na porta 1025 e interface na 8025.

## 12. Navegador chama a API diretamente

Deixa os status reais visíveis nas ferramentas do navegador e diferencia a falha de rede, quando nenhuma stack está no ar, de um erro da API.

**Custo:** cada API precisa configurar CORS.

## 13. Escopo das convenções do `AGENTS.md`

O `AGENTS.md` em `~/Documents` descreve outro produto, uma plataforma de eventos com upload de mídia. Este projeto adota apenas as convenções gerais:

- Documentação em português do Brasil e código em inglês.
- Organização modular.
- Formato das respostas JSON, com o corpo de erro redefinido pela decisão 14, e das mensagens de commit.

Não se aplicam aqui as regras específicas daquele produto, como a arquitetura de upload, a estrutura de filas de mídia e o prefixo `/api/v1`.

## 14. Forma única das respostas de erro

Todo erro de `POST /users` traz `message` e uma lista `errors`, com `field`, `code` e `message` em cada item. A lista fica vazia quando não há erro de campo. O frontend traduz cada item pelo par `field` + `code`, e a API continua em inglês. O detalhamento está em [api-contract.md](api-contract.md#forma-do-corpo-de-erro) e no [design](../.design/api-error-response.md).

**Motivos**
- **Uma forma só:** os status de erro tinham corpos diferentes, e cada stack teria de decidir como montá-los.
- **Tradução sem comparar textos:** o 422 mostra o erro junto de cada campo, e o status não diz qual regra foi violada.
- **Lista em vez de mapa:** sem erro de campo, um mapa vazio sairia como `[]` em PHP e `null` em Go, se não fosse tratado. Em Go, a lista também precisa ser inicializada.

**Alternativas descartadas**
- **Mapa por campo:** mantinha o agrupamento do formato anterior, mas exigia tratar o mapa vazio em cada stack.
- **RFC 9457 (Problem Details):** só compensa com consumidores externos ou ferramentas que esperem o padrão, e hoje há um endpoint e um frontend.
- **Mensagens da API em português:** simplificaria o frontend, mas colocaria texto de interface nas três stacks.

**Custos**
- Nenhuma stack aproveita o formato de erro nativo do framework.
- Os códigos e o par `field` + `code` passam a ser um contrato entre as stacks e o frontend.
- 404, 405, `Content-Type` errado, corpo que não é objeto e a quantidade de erros por campo ficam sem definição, conforme as [limitações do contrato](api-contract.md#limitações-conhecidas).

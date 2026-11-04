# Forma única das respostas de erro da API

> Plan from this document. Each slice below carries its own shape - copy it, do not re-derive it.
> Status: confirmed by diashelter, 2026-11-04

## Situation

- Project: em construção; o repositório só tem documentação, sem nenhuma das três stacks nem o frontend.
- Decision: committed by diashelter, 2026-11-04, nesta sessão ("vamos padronizar").
- In flight: mantém o corpo de sucesso `data` + `message` e o par `message` + `errors` do contrato atual, cujo formato a decisão 13 atribui a um `AGENTS.md` que não está mais no caminho citado. Outbox, filas, limite de tentativas e rota ficam de fora.
- At stake: reverte-se em uma tarde enquanto nada foi implementado; depois, cada mudança custa três stacks e o frontend.

## Problem

O contrato promete que as três stacks respondem exatamente igual e que o frontend não sabe qual delas está no ar. Hoje os cinco status de `POST /users` usam três corpos diferentes (`data` + `message`, `message` + `errors`, só `message`), então o tratamento de erro de cada stack e o formulário não têm uma forma única para seguir, e esse trabalho seria escrito quatro vezes.

O documento também se contradiz: a API responde em inglês e o frontend traduz por status, mas o 422 precisa mostrar um erro junto de cada campo, e o status não diz qual regra foi violada.

Precisa ser agora porque nenhuma linha foi escrita e esta é a primeira peça de que as stacks e o formulário dependem. Nada disso foi medido, porque ainda não há produto; a evidência é o próprio contrato.

## Success

- Worked if: os corpos de 409, 422, 429 e 500 têm a mesma forma nas três stacks nos testes de feature já previstos, e o formulário mostra o texto em português sem comparar nenhuma mensagem em inglês.

## Boundary

In: corpo de erro de 409, 422, 429 e 500 em `POST /users`; vocabulário de códigos dos erros de campo; tradução desses códigos no formulário.

Out:
- 404, 405, `Content-Type` errado e corpo que não é objeto - fora desta rodada por escolha; cada framework responde do seu jeito, e o formulário cai no texto do 500.
- Quantidade de itens por campo - fora desta rodada; um e-mail longo e inválido pode trazer um ou dois itens, conforme a stack, e o texto exibido pode variar entre elas.
- Arquivo de schema e teste único contra as três stacks - fora desta rodada; a igualdade continua sendo cobrada pelos testes de cada stack. Reabrir se as stacks divergirem.

Unchanged: status HTTP, ordem de processamento, header `Retry-After`, limite de tentativas, corpo do 201, rota `POST /users` e o texto das mensagens em inglês.

## Prior art

- `errors` como lista de objetos aparece no exemplo de validação da RFC 9457 e no exemplo de 422 da documentação do NestJS - adotamos a lista.
- A RFC 9457 orienta os consumidores a não extrair informação de `detail` e a usar membros próprios - adotamos a mesma regra para `message` (Key decision 2).
- A RFC 9457 também define `application/problem+json` e os membros `type`, `title`, `status` e `detail` - não adotamos, porque serve a consumidores e ferramentas genéricas que este projeto não tem.

## Shape

O corpo de erro passa a ser um único registro com `message` e uma lista `errors`, em que cada item identifica o campo e a regra violada. Toda resposta de erro de `POST /users` usa esse registro, e o formulário traduz cada item para o português. A porta é o par `field` + `code`, consumido pelo frontend: trocá-lo depois exige alterar as três stacks e o formulário juntos, enquanto acrescentar um membro não quebra ninguém.

Adotar a RFC 9457 só compensa com consumidores externos ou ferramentas que esperem o padrão, e hoje há um endpoint e um frontend. Esta forma não sobrevive a essa exigência sem reescrever o corpo.

## Key decisions

1. **Todo corpo de erro tem `message` e `errors`, e `errors` é sempre uma lista, nunca ausente nem nula.** Sem erro de campo, a lista vem vazia. Uma lista foi escolhida em vez do mapa por campo porque um mapa vazio sai como `[]` em PHP e `null` em Go, se não for tratado; em Go, a lista também precisa ser inicializada para não sair como `null`.
2. **`field` e `code` são o contrato; `message` serve para diagnóstico.** Nenhum consumidor compara ou exibe `message`. Mudar um texto em inglês não quebra o formulário; mudar um `code` quebra.
3. **`code` identifica a regra, não o campo, e o vocabulário é fechado.** Os valores são `required`, `too_long`, `invalid_format` e `already_taken`, em `snake_case` como os demais membros JSON. Um valor novo é uma mudança de contrato.
4. **No nível de cima, quem identifica o caso é o status HTTP, sem `code` próprio.** Hoje cada status tem uma única causa. Se um status passar a ter duas, acrescenta-se um `code` de topo sem quebrar quem já consome.
5. **Texto em português existe só no frontend, e a API continua em inglês.** Isso resolve a contradição do contrato atual e mantém texto de interface fora das stacks.
6. **`data` só aparece em sucesso, `errors` só em erro, e `message` em todos os corpos.** O 201 não muda.
7. **Nenhuma stack usa o formato de erro nativo do framework.** O padrão do Laravel é tentador por ser parecido, mas traz `(and N more errors)` em `message` e textos soltos em `errors`; não copie.

## Work

| Slice | Delivers | Status |
|---|---|---|
| [ErrorResponse](#errorresponse) | Corpo de erro único, com a tabela de códigos, no contrato e nas três stacks | clear |
| [RegistrationForm](#registrationform) | Formulário que traduz por `field` + `code` e tem uma saída para respostas fora do contrato | open - 1 default taken |

Order: ErrorResponse → RegistrationForm.

Já definido no contrato atual: 201, falha de rede e os textos de 429 e 500 no formulário.

Derivável do contrato atual, deixado para o plano: ajuste dos exemplos e tabelas de respostas e o novo registro no histórico de decisões, como pede o cabeçalho desse histórico.

### ErrorResponse

**Delivers** a forma única de erro em `POST /users`, escrita no contrato e aplicada nas três stacks. **Status: clear.** É a porta do design.

| State | What should happen | Caller sees |
|---|---|---|
| Campo ausente, vazio ou de tipo incorreto | Nada é gravado e a tentativa não conta | 422, `The given data was invalid.`, item `required` no campo |
| JSON malformado | Nada é gravado e a tentativa não conta | 422, `The given data was invalid.`, itens `required` em `name` e `email` |
| Campo acima do limite | Nada é gravado e a tentativa não conta | 422, `The given data was invalid.`, item `too_long` no campo |
| E-mail com formato inválido | Nada é gravado e a tentativa não conta | 422, `The given data was invalid.`, item `invalid_format` em `email` |
| E-mail já cadastrado | Nem usuário nem evento são gravados | 409, `The email has already been taken.`, item `already_taken` em `email` |
| Limite de tentativas excedido | O banco não é consultado | 429, `Too many registration attempts. Try again later.`, `errors` vazio, com `Retry-After` |
| Banco ou `redis-limiter` indisponível, ou erro inesperado | A causa vai para os logs, sem detalhe interno na resposta | 500, `Internal server error.`, `errors` vazio |

`POST /users` `{ name, email }` → `201` `{ data: { id, name, email, created_at }, message }`

Corpo de 409, 422, 429 e 500:

```json
{
  "message": "The given data was invalid.",
  "errors": [
    {
      "field": "email",
      "code": "invalid_format",
      "message": "The email must be a valid email address."
    }
  ]
}
```

| `field` | `code` | `message` |
|---|---|---|
| `name` | `required` | `The name field is required.` |
| `name` | `too_long` | `The name must not exceed 255 characters.` |
| `email` | `required` | `The email field is required.` |
| `email` | `invalid_format` | `The email must be a valid email address.` |
| `email` | `too_long` | `The email must not exceed 254 characters.` |
| `email` | `already_taken` | `The email has already been taken.` |

Alternatives considered: `errors` como mapa por campo - vence se a lista vazia deixar de existir, porque aí o problema de serialização desaparece.

### RegistrationForm

**Delivers** o formulário lendo a forma única e traduzindo cada item de `errors` para o português. **Status: open.**

| State | What should happen | Caller sees |
|---|---|---|
| 409 ou 422 com itens em `errors` | Cada campo mostra o texto do seu primeiro item | Texto da tabela abaixo, junto do campo |
| Par `field` + `code` sem texto conhecido | O campo continua marcado, sem expor o inglês | `Verifique este campo.` |
| Status fora da tabela do contrato, ou corpo fora da forma única | O formulário não tenta interpretar a resposta | Mesmo texto do 500 |

| `field` | `code` | Texto |
|---|---|---|
| `name` | `required` | Informe seu nome. |
| `name` | `too_long` | O nome deve ter no máximo 255 caracteres. |
| `email` | `required` | Informe seu e-mail. |
| `email` | `invalid_format` | Informe um e-mail válido. |
| `email` | `too_long` | O e-mail deve ter no máximo 254 caracteres. |
| `email` | `already_taken` | Este e-mail já está cadastrado. |

Open, default taken:
1. Redação dos textos em português - os da tabela acima; só o de `already_taken` já existia no contrato.

## Sources

- [Contrato da API](../docs/api-contract.md) - respostas, mensagens canônicas e comportamento do frontend atuais.
- [Registro de decisões](../docs/decisions.md) - decisões 3, 7 e 13.
- [Stacks](../docs/stacks.md) - testes previstos em cada stack e filtro de exceções do NestJS.
- [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457.html) - membros, media type, extensão `errors` e orientação sobre `detail`.
- [Validação no Laravel](https://github.com/laravel/docs/blob/13.x/validation.md) - formato padrão do 422.
- [Validação no NestJS](https://github.com/nestjs/docs.nestjs.com/blob/master/content/application/validation.md) - `exceptionFactory` e exemplo de 422 com `errors` em lista.

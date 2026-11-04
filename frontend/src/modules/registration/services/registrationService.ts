import { parseErrorBody } from "../schemas/registrationSchema";
import type {
  RegistrationField,
  RegistrationInput,
  RegistrationResult,
} from "../types/registration";

// Chama POST /users direto do navegador e traduz a resposta para o texto que o
// formulário mostra. Textos: docs/api-contract.md › Comportamento do frontend.

export const TEXTS = {
  success: "Recebemos seus dados! Em instantes você receberá um e-mail de confirmação.",
  failure: "Não foi possível concluir seu cadastro. Tente novamente em instantes.",
  network: "Serviço indisponível no momento. Tente novamente em instantes.",
  tooManyLater: "Muitas tentativas de cadastro. Tente novamente mais tarde.",
  unknownCode: "Verifique este campo.",
} as const;

const FIELD_TEXTS: Record<RegistrationField, Record<string, string>> = {
  name: {
    required: "Informe seu nome.",
    too_long: "O nome deve ter no máximo 255 caracteres.",
  },
  email: {
    required: "Informe seu e-mail.",
    invalid_format: "Informe um e-mail válido.",
    too_long: "O e-mail deve ter no máximo 254 caracteres.",
    already_taken: "Este e-mail já está cadastrado.",
  },
};

const FIELDS: RegistrationField[] = ["name", "email"];

function message(text: string): RegistrationResult {
  return { kind: "message", message: text };
}

function usersUrl(): string {
  const base = (process.env.NEXT_PUBLIC_API_URL ?? "").replace(/\/+$/, "");
  return `${base}/users`;
}

// 429: minutos arredondados para cima a partir do Retry-After, no mínimo 1.
function tooManyAttempts(retryAfter: string | null): RegistrationResult {
  if (retryAfter === null || !/^[0-9]+$/.test(retryAfter)) return message(TEXTS.tooManyLater);
  const minutes = Math.max(1, Math.ceil(Number(retryAfter) / 60));
  const unit = minutes === 1 ? "minuto" : "minutos";
  return message(`Muitas tentativas de cadastro. Tente novamente em ${minutes} ${unit}.`);
}

// 409 e 422: o texto do primeiro item de cada campo; fora da forma única, ou sem
// item de name ou email, o mesmo texto do 500.
async function fieldErrors(response: Response): Promise<RegistrationResult> {
  let body: unknown;
  try {
    body = await response.json();
  } catch {
    return message(TEXTS.failure);
  }
  const parsed = parseErrorBody(body);
  if (parsed === null) return message(TEXTS.failure);

  const fields: Partial<Record<RegistrationField, string>> = {};
  for (const field of FIELDS) {
    const first = parsed.errors.find((item) => item.field === field);
    if (first) fields[field] = FIELD_TEXTS[field][first.code] ?? TEXTS.unknownCode;
  }
  if (Object.keys(fields).length === 0) return message(TEXTS.failure);
  return { kind: "fields", fields };
}

export async function register(input: RegistrationInput): Promise<RegistrationResult> {
  let response: Response;
  try {
    response = await fetch(usersUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ name: input.name, email: input.email }),
    });
  } catch {
    // Sem resposta: nenhuma stack no ar, ou CORS recusado.
    return message(TEXTS.network);
  }

  switch (response.status) {
    case 201:
      // O cadastro já foi gravado: o corpo não é lido.
      return message(TEXTS.success);
    case 409:
    case 422:
      return fieldErrors(response);
    case 429:
      return tooManyAttempts(response.headers.get("Retry-After"));
    default:
      return message(TEXTS.failure);
  }
}

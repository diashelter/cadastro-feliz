import type { ApiErrorBody, ApiFieldError } from "../types/registration";

// Valida a forma única de erro da API (docs/api-contract.md › Forma do corpo de
// erro). O formulário não valida a entrada: quem valida é a API.

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isFieldError(value: unknown): value is ApiFieldError {
  return (
    isRecord(value) &&
    typeof value.field === "string" &&
    typeof value.code === "string" &&
    typeof value.message === "string"
  );
}

// Devolve o corpo quando ele segue a forma única, ou null quando não segue.
export function parseErrorBody(value: unknown): ApiErrorBody | null {
  if (!isRecord(value) || typeof value.message !== "string") return null;
  if (!Array.isArray(value.errors) || !value.errors.every(isFieldError)) return null;
  return { message: value.message, errors: value.errors };
}

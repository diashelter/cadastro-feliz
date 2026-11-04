// Tipos do cadastro. Contrato: docs/api-contract.md › POST /users.

export type RegistrationInput = {
  name: string;
  email: string;
};

export type RegistrationField = keyof RegistrationInput;

// Um item de `errors` na forma única de erro da API.
export type ApiFieldError = {
  field: string;
  code: string;
  message: string;
};

export type ApiErrorBody = {
  message: string;
  errors: ApiFieldError[];
};

// O que o formulário mostra depois de uma resposta, já em português.
export type RegistrationResult =
  | { kind: "message"; message: string }
  | { kind: "fields"; fields: Partial<Record<RegistrationField, string>> };

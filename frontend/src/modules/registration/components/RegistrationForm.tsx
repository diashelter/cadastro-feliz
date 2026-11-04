"use client";

import { useRef, useState, type FormEvent } from "react";
import { register } from "../services/registrationService";
import type { RegistrationField, RegistrationResult } from "../types/registration";

// Envia o que foi digitado, sem validar no navegador: os erros de campo vêm da
// API (decisão 18 de docs/decisions.md).

const LABELS: Record<RegistrationField, string> = { name: "Nome", email: "E-mail" };
// O e-mail usa `type="text"`: um campo `type="email"` tira os espaços das pontas
// do valor, e o formulário envia exatamente o que foi digitado.
const INPUT_MODES: Record<RegistrationField, "text" | "email"> = { name: "text", email: "email" };

export default function RegistrationForm() {
  const [values, setValues] = useState({ name: "", email: "" });
  const [pending, setPending] = useState(false);
  const [result, setResult] = useState<RegistrationResult | null>(null);
  // Barra um segundo envio antes de o botão desabilitado ser renderizado.
  const inFlight = useRef(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (inFlight.current) return;
    inFlight.current = true;
    setPending(true);
    setResult(null);
    try {
      setResult(await register(values));
    } finally {
      inFlight.current = false;
      setPending(false);
    }
  }

  const fieldTexts = result?.kind === "fields" ? result.fields : {};
  const general = result?.kind === "message" ? result.message : "";

  return (
    <form className="registration" noValidate onSubmit={handleSubmit}>
      {(Object.keys(LABELS) as RegistrationField[]).map((field) => {
        const id = `registration-${field}`;
        const text = fieldTexts[field];
        return (
          <div className="registration-field" key={field}>
            <label htmlFor={id}>{LABELS[field]}</label>
            <input
              id={id}
              name={field}
              type="text"
              inputMode={INPUT_MODES[field]}
              autoComplete={field}
              value={values[field]}
              onChange={(event) => setValues({ ...values, [field]: event.target.value })}
              aria-invalid={text ? true : undefined}
              aria-describedby={text ? `${id}-error` : undefined}
            />
            {text && (
              <p className="registration-error" id={`${id}-error`}>
                {text}
              </p>
            )}
          </div>
        );
      })}
      <button type="submit" disabled={pending}>
        {pending ? "Enviando…" : "Cadastrar"}
      </button>
      <p className="registration-status" role="status">
        {general}
      </p>
    </form>
  );
}

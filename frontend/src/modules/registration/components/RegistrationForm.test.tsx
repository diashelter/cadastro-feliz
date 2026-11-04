import { describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import RegistrationForm from "./RegistrationForm";

// Respostas simuladas de POST /users, conforme docs/api-contract.md.
// Os casos vêm dos checks de .specs/features/registration-form/checks.md.

const API = "http://localhost:8080";

const SUCCESS = "Recebemos seus dados! Em instantes você receberá um e-mail de confirmação.";
const FAILURE = "Não foi possível concluir seu cadastro. Tente novamente em instantes.";
const NETWORK = "Serviço indisponível no momento. Tente novamente em instantes.";
const LATER = "Muitas tentativas de cadastro. Tente novamente mais tarde.";
const CHECK_FIELD = "Verifique este campo.";

type Reply = { status: number; body?: string; headers?: Record<string, string> };

function json(value: unknown): string {
  return JSON.stringify(value);
}

function errorBody(items: Array<{ field: string; code: string; message?: string }>): string {
  return json({
    message: "The given data was invalid.",
    errors: items.map((item) => ({ message: "Canonical message.", ...item })),
  });
}

function reply({ status, body = "", headers = {} }: Reply): Response {
  return new Response(body === "" ? null : body, { status, headers });
}

function stubFetch(...replies: Reply[]) {
  const fetchMock = vi.fn();
  for (const r of replies) fetchMock.mockResolvedValueOnce(reply(r));
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

// Uma resposta que só chega quando o teste mandar.
function stubPendingFetch() {
  let resolve: (response: Response) => void = () => {};
  const fetchMock = vi.fn(
    () =>
      new Promise<Response>((r) => {
        resolve = r;
      }),
  );
  vi.stubGlobal("fetch", fetchMock);
  return { fetchMock, respond: (r: Reply) => resolve(reply(r)) };
}

function setup() {
  vi.stubEnv("NEXT_PUBLIC_API_URL", API);
  const user = userEvent.setup();
  const view = render(<RegistrationForm />);
  const name = screen.getByLabelText("Nome") as HTMLInputElement;
  const email = screen.getByLabelText("E-mail") as HTMLInputElement;
  const button = () => screen.getByRole("button") as HTMLButtonElement;
  return { user, view, name, email, button };
}

async function submit(values: { name?: string; email?: string }, ...replies: Reply[]) {
  const fetchMock = stubFetch(...replies);
  const form = setup();
  if (values.name) await form.user.type(form.name, values.name);
  if (values.email) await form.user.type(form.email, values.email);
  await form.user.click(form.button());
  await waitFor(() => expect(form.button().disabled).toBe(false));
  return { ...form, fetchMock };
}

function statusText(): string {
  return screen.getByRole("status").textContent ?? "";
}

// Texto ligado ao campo por aria-describedby, ou "" quando não há.
function fieldText(input: HTMLInputElement): string {
  const id = input.getAttribute("aria-describedby");
  if (!id) return "";
  return document.getElementById(id)?.textContent ?? "";
}

describe("RegistrationForm", () => {
  it("sends one POST with the typed values as JSON", async () => {
    const { fetchMock } = await submit(
      { name: "  Ana Souza ", email: " ANA@Example.com" },
      { status: 201 },
    );
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("http://localhost:8080/users");
    expect(init.method).toBe("POST");
    const headers = new Headers(init.headers);
    expect(headers.get("Content-Type")).toBe("application/json");
    expect(headers.get("Accept")).toBe("application/json");
    expect(JSON.parse(init.body)).toEqual({ name: "  Ana Souza ", email: " ANA@Example.com" });
  });

  it("joins an API address that ends with a slash", async () => {
    const fetchMock = stubFetch({ status: 201 });
    const { user, button } = setup();
    vi.stubEnv("NEXT_PUBLIC_API_URL", "http://localhost:8080/");
    await user.click(button());
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    expect(fetchMock.mock.calls[0][0]).toBe("http://localhost:8080/users");
  });

  it("sends empty fields without browser validation", async () => {
    const { fetchMock, name, email, view } = await submit({}, { status: 201 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ name: "", email: "" });
    const form = view.container.querySelector("form") as HTMLFormElement;
    expect(form.noValidate).toBe(true);
    for (const input of [name, email]) {
      expect(input.hasAttribute("required")).toBe(false);
      expect(input.hasAttribute("maxlength")).toBe(false);
      expect(input.hasAttribute("pattern")).toBe(false);
    }
  });

  it("sends an invalid email without browser validation", async () => {
    const { fetchMock } = await submit({ name: "Ana", email: "não-é-email" }, { status: 201 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({
      name: "Ana",
      email: "não-é-email",
    });
  });

  it("disables the button with Enviando… while waiting", async () => {
    const { respond } = stubPendingFetch();
    const { user, button } = setup();
    expect(button().textContent).toBe("Cadastrar");
    await user.click(button());
    expect(button().disabled).toBe(true);
    expect(button().textContent).toBe("Enviando…");
    respond({ status: 201 });
    await waitFor(() => expect(button().disabled).toBe(false));
    expect(button().textContent).toBe("Cadastrar");
  });

  it("sends one request for two quick clicks", async () => {
    const { fetchMock, respond } = stubPendingFetch();
    const { user, button } = setup();
    await user.dblClick(button());
    await user.click(button());
    expect(fetchMock).toHaveBeenCalledTimes(1);
    respond({ status: 201 });
    await waitFor(() => expect(button().disabled).toBe(false));
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("sends a second request after the response", async () => {
    const fetchMock = stubFetch({ status: 201 }, { status: 201 });
    const { user, button } = setup();
    await user.click(button());
    await waitFor(() => expect(statusText()).toBe(SUCCESS));
    await user.click(button());
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
  });

  it("shows success for a 201 with any body", async () => {
    const bodies = [
      json({
        data: { id: "0190f3a2", name: "Ana Souza", email: "ana@example.com", created_at: "2026-11-04T12:00:00Z" },
        message: "User registered successfully.",
      }),
      "{}",
      "",
      "não é json",
    ];
    for (const body of bodies) {
      const { view } = await submit({ name: "Ana" }, { status: 201, body });
      expect(statusText(), `corpo ${JSON.stringify(body)}`).toBe(SUCCESS);
      view.unmount();
    }
  });

  it("keeps the typed values after a 201", async () => {
    const { name, email, button } = await submit(
      { name: "Ana Souza", email: "ana@example.com" },
      { status: 201 },
    );
    expect(statusText()).toBe(SUCCESS);
    expect(name.value).toBe("Ana Souza");
    expect(email.value).toBe("ana@example.com");
    expect(button().disabled).toBe(false);
  });

  it("shows the first item of each field", async () => {
    const { name, email } = await submit(
      {},
      {
        status: 422,
        body: errorBody([
          { field: "name", code: "required" },
          { field: "email", code: "invalid_format" },
        ]),
      },
    );
    expect(fieldText(name)).toBe("Informe seu nome.");
    expect(fieldText(email)).toBe("Informe um e-mail válido.");
    expect(statusText()).toBe("");
  });

  it("shows only the first item when a field has two", async () => {
    const { name, email } = await submit(
      {},
      {
        status: 422,
        body: errorBody([
          { field: "email", code: "too_long" },
          { field: "email", code: "invalid_format" },
        ]),
      },
    );
    expect(fieldText(email)).toBe("O e-mail deve ter no máximo 254 caracteres.");
    expect(fieldText(name)).toBe("");
    expect(screen.queryByText("Informe um e-mail válido.")).toBeNull();
    expect(statusText()).toBe("");
  });

  it("shows already_taken on the email field for a 409", async () => {
    const { name, email } = await submit(
      { name: "Ana", email: "ana@example.com" },
      { status: 409, body: errorBody([{ field: "email", code: "already_taken" }]) },
    );
    expect(fieldText(email)).toBe("Este e-mail já está cadastrado.");
    expect(fieldText(name)).toBe("");
    expect(statusText()).toBe("");
  });

  it("maps every field and code to its text", async () => {
    const table: Array<[string, string, string]> = [
      ["name", "required", "Informe seu nome."],
      ["name", "too_long", "O nome deve ter no máximo 255 caracteres."],
      ["email", "required", "Informe seu e-mail."],
      ["email", "invalid_format", "Informe um e-mail válido."],
      ["email", "too_long", "O e-mail deve ter no máximo 254 caracteres."],
      ["email", "already_taken", "Este e-mail já está cadastrado."],
    ];
    for (const [field, code, text] of table) {
      const { name, email, view } = await submit(
        {},
        { status: 422, body: errorBody([{ field, code }]) },
      );
      expect(fieldText(field === "name" ? name : email), `${field}/${code}`).toBe(text);
      expect(fieldText(field === "name" ? email : name), `${field}/${code}`).toBe("");
      view.unmount();
    }
  });

  it("shows Verifique este campo. for an unknown code", async () => {
    const cases: Array<[string, string]> = [
      ["email", "blocked"],
      ["name", "already_taken"],
    ];
    for (const [field, code] of cases) {
      const { name, email, view } = await submit(
        {},
        { status: 409, body: errorBody([{ field, code }]) },
      );
      expect(fieldText(field === "name" ? name : email), `${field}/${code}`).toBe(CHECK_FIELD);
      expect(statusText()).toBe("");
      view.unmount();
    }
  });

  it("treats a field error body outside the contract as a 500", async () => {
    const bodies: Array<[string, string]> = [
      ["errors vazio", json({ message: "The given data was invalid.", errors: [] })],
      ["só phone", errorBody([{ field: "phone", code: "required" }])],
      ["errors ausente", json({ message: "The given data was invalid." })],
      ["errors null", json({ message: "The given data was invalid.", errors: null })],
      [
        "item sem code",
        json({
          message: "The given data was invalid.",
          errors: [
            { field: "name", code: "required", message: "The name field is required." },
            { field: "email", message: "The email must be a valid email address." },
          ],
        }),
      ],
      ["não é json", "não é json"],
    ];
    for (const status of [409, 422]) {
      for (const [label, body] of bodies) {
        const { name, email, view } = await submit({}, { status, body });
        expect(statusText(), `${status} ${label}`).toBe(FAILURE);
        expect(fieldText(name), `${status} ${label}`).toBe("");
        expect(fieldText(email), `${status} ${label}`).toBe("");
        view.unmount();
      }
    }
  });

  it("shows the minutes of a 429 rounded up", async () => {
    const table: Array<[string, string]> = [
      ["742", "Muitas tentativas de cadastro. Tente novamente em 13 minutos."],
      ["900", "Muitas tentativas de cadastro. Tente novamente em 15 minutos."],
      ["61", "Muitas tentativas de cadastro. Tente novamente em 2 minutos."],
      ["60", "Muitas tentativas de cadastro. Tente novamente em 1 minuto."],
      ["0", "Muitas tentativas de cadastro. Tente novamente em 1 minuto."],
    ];
    for (const [seconds, text] of table) {
      const { view } = await submit(
        {},
        {
          status: 429,
          body: json({ message: "Too many registration attempts. Try again later.", errors: [] }),
          headers: { "Retry-After": seconds },
        },
      );
      expect(statusText(), `Retry-After ${seconds}`).toBe(text);
      view.unmount();
    }
  });

  it("shows mais tarde for a 429 without a readable Retry-After", async () => {
    const values: Array<string | null> = [null, "abc", "-5", "12.5", "Wed, 21 Oct 2026 07:28:00 GMT"];
    for (const value of values) {
      const { view } = await submit(
        {},
        {
          status: 429,
          body: json({ message: "Too many registration attempts. Try again later.", errors: [] }),
          headers: value === null ? {} : { "Retry-After": value },
        },
      );
      expect(statusText(), `Retry-After ${value}`).toBe(LATER);
      view.unmount();
    }
  });

  it("shows the 500 text for a 500", async () => {
    await submit({}, { status: 500, body: json({ message: "Internal server error.", errors: [] }) });
    expect(statusText()).toBe(FAILURE);
  });

  it("shows the 500 text for a status outside the contract", async () => {
    for (const status of [200, 400, 404, 405, 503]) {
      const { name, email, view } = await submit(
        {},
        { status, body: errorBody([{ field: "email", code: "invalid_format" }]) },
      );
      expect(statusText(), `status ${status}`).toBe(FAILURE);
      expect(fieldText(name), `status ${status}`).toBe("");
      expect(fieldText(email), `status ${status}`).toBe("");
      view.unmount();
    }
  });

  it("shows the network failure text when fetch rejects", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")));
    const { user, button } = setup();
    await user.click(button());
    await waitFor(() => expect(statusText()).toBe(NETWORK));
    expect(button().disabled).toBe(false);
  });

  it("clears field texts when a new request starts", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        reply({
          status: 422,
          body: errorBody([
            { field: "name", code: "required" },
            { field: "email", code: "required" },
          ]),
        }),
      )
      .mockImplementationOnce(() => new Promise<Response>(() => {}));
    vi.stubGlobal("fetch", fetchMock);
    const { user, button, name, email } = setup();
    await user.click(button());
    await waitFor(() => expect(fieldText(name)).toBe("Informe seu nome."));
    await user.click(button());
    expect(button().disabled).toBe(true);
    expect(fieldText(name)).toBe("");
    expect(fieldText(email)).toBe("");
    expect(screen.queryByText("Informe seu nome.")).toBeNull();
    expect(screen.queryByText("Informe seu e-mail.")).toBeNull();
  });

  it("clears the general message when a new request starts", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(reply({ status: 201 }))
      .mockImplementationOnce(() => new Promise<Response>(() => {}));
    vi.stubGlobal("fetch", fetchMock);
    const { user, button } = setup();
    await user.click(button());
    await waitFor(() => expect(statusText()).toBe(SUCCESS));
    await user.click(button());
    expect(button().disabled).toBe(true);
    expect(statusText()).toBe("");
  });

  it("describes each field with its text", async () => {
    const { name, email } = await submit(
      {},
      {
        status: 422,
        body: errorBody([
          { field: "name", code: "too_long" },
          { field: "email", code: "already_taken" },
        ]),
      },
    );
    for (const [input, text] of [
      [name, "O nome deve ter no máximo 255 caracteres."],
      [email, "Este e-mail já está cadastrado."],
    ] as const) {
      const id = input.getAttribute("aria-describedby");
      expect(id).toBeTruthy();
      expect(document.getElementById(id as string)?.textContent).toBe(text);
      expect(input.getAttribute("aria-invalid")).toBe("true");
    }
  });

  it("announces the general message in a status", async () => {
    await submit({}, { status: 500 });
    const status = screen.getByRole("status");
    expect(status.textContent).toBe(FAILURE);
    expect(screen.getAllByText(FAILURE)).toEqual([status]);
  });
});

import { readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import Home from "./page";

// O título é montado aqui para que este arquivo não contenha o texto: os testes
// de tests/infra/frontend.sh trocam o título em page.tsx e esperam que ele suma.
const TITLE = ["Cadastro", "Feliz"].join(" ");
const SRC = join(__dirname, "..");

function filesUnder(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory() ? filesUnder(join(dir, entry.name)) : [join(dir, entry.name)],
  );
}

describe("Home", () => {
  it("shows the title, the API address and the empty form", () => {
    vi.stubEnv("NEXT_PUBLIC_API_URL", "http://localhost:8080");
    render(<Home />);
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe(TITLE);
    expect(screen.getByText("http://localhost:8080", { exact: false })).toBeTruthy();
    expect((screen.getByLabelText("Nome") as HTMLInputElement).value).toBe("");
    expect((screen.getByLabelText("E-mail") as HTMLInputElement).value).toBe("");
    const button = screen.getByRole("button") as HTMLButtonElement;
    expect(button.textContent).toBe("Cadastrar");
    expect(button.disabled).toBe(false);
    expect(screen.getByRole("status").textContent).toBe("");
    expect(screen.getByLabelText("Nome").getAttribute("aria-describedby")).toBeNull();
    expect(screen.getByLabelText("E-mail").getAttribute("aria-describedby")).toBeNull();
  });

  it(`keeps ${TITLE} only in page.tsx`, () => {
    const holders = filesUnder(SRC)
      .filter((file) => readFileSync(file, "utf8").includes(TITLE))
      .map((file) => relative(SRC, file));
    expect(holders).toEqual([join("app", "page.tsx")]);
  });
});

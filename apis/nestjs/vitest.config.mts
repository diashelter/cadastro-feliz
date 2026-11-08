import swc from "unplugin-swc";
import { defineConfig } from "vitest/config";

// O Vitest sozinho não emite os metadados de decorators de que o Nest precisa: a receita
// oficial do Nest compila os testes com o SWC (decisão 25 de docs/decisions.md).
export default defineConfig({
  plugins: [swc.vite({ module: { type: "es6" } })],
  test: {
    include: ["src/**/*.spec.ts"],
  },
});

import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

// Testes de componente em jsdom, como no guia de testes do Next.js.
// Referência: .design/registration-form.md.
export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    setupFiles: ["./vitest.setup.ts"],
  },
});

import { afterEach, vi } from "vitest";
import { cleanup } from "@testing-library/react";

// Sem `globals`, o Testing Library não desmonta sozinho entre os testes.
afterEach(() => {
  cleanup();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

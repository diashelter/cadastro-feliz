import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Cadastro Feliz",
};

export default function Home() {
  return (
    <main>
      <h1>Cadastro Feliz</h1>
      <p>API: {process.env.NEXT_PUBLIC_API_URL}</p>
    </main>
  );
}

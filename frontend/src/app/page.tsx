import type { Metadata } from "next";
import RegistrationForm from "../modules/registration/components/RegistrationForm";

export const metadata: Metadata = {
  title: "Cadastro Feliz",
};

export default function Home() {
  return (
    <main>
      <h1>Cadastro Feliz</h1>
      <p className="api-address">API: {process.env.NEXT_PUBLIC_API_URL}</p>
      <RegistrationForm />
    </main>
  );
}

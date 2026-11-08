// O e-mail de boas-vindas, igual nas três stacks (docs/architecture.md › E-mail enviado).

export const WELCOME_SUBJECT = 'Boas-vindas ao Cadastro Feliz!';
export const SENDER_NAME = 'Cadastro Feliz';

/** O mesmo evento sai sempre com o mesmo Message-ID, nas três stacks (decisão 22). */
export function messageIdFor(eventId: string): string {
  return `<${eventId}@cadastro-feliz.local>`;
}

export function escapeHtml(text: string): string {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

export function welcomeText(name: string): string {
  return `Olá, ${name}!

Que bom ter você por aqui. Seu cadastro no Cadastro Feliz foi concluído com sucesso.

Não é preciso fazer mais nada.

Um abraço,
Equipe Cadastro Feliz
`;
}

export function welcomeHtml(name: string): string {
  return `<!doctype html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${WELCOME_SUBJECT}</title>
</head>
<body style="margin:0;padding:32px 16px;background:#f7f7f5;color:#27272a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:16px;line-height:1.6;">
    <div style="max-width:480px;margin:0 auto;padding:32px;background:#ffffff;border-radius:12px;">
        <h1 style="margin:0 0 16px;font-size:22px;font-weight:600;line-height:1.3;">Olá, ${escapeHtml(name)}!</h1>
        <p style="margin:0 0 16px;">Que bom ter você por aqui. Seu cadastro no Cadastro Feliz foi concluído com sucesso.</p>
        <p style="margin:0 0 24px;">Não é preciso fazer mais nada.</p>
        <p style="margin:0;">Um abraço,<br>Equipe Cadastro Feliz</p>
    </div>
</body>
</html>
`;
}

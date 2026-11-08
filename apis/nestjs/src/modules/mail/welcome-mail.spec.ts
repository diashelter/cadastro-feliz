import { describe, expect, it } from 'vitest';
import { messageIdFor, welcomeHtml, welcomeText } from './welcome-mail';

describe('welcome mail', () => {
  it('message id derives from the event', () => {
    expect(messageIdFor('5f0c3d1e-0000-4000-8000-000000000001')).toBe(
      '<5f0c3d1e-0000-4000-8000-000000000001@cadastro-feliz.local>',
    );
  });

  it('escapes the name in html', () => {
    const html = welcomeHtml('<b>Ana</b> & "Bia"');
    expect(html).toContain('Olá, &lt;b&gt;Ana&lt;/b&gt; &amp; &quot;Bia&quot;!');
    expect(html).not.toContain('<b>Ana</b>');
  });

  it('keeps the name as is in the text part', () => {
    expect(welcomeText('Ana <b>Souza</b>')).toContain('Olá, Ana <b>Souza</b>!');
  });
});

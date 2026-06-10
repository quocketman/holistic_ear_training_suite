/**
 * Cloudflare Worker — Mailchimp signup proxy for the Tune Indigo Whiteboard.
 *
 * Sits between the SPA at whiteboard.tuneindigo.com and the Mailchimp API.
 * Keeps the Mailchimp API key off the public client, handles CORS, and
 * normalises the "Member Exists" case into a success response.
 *
 * Wire (Cloudflare side):
 *   1. Cloudflare dashboard → Workers & Pages → Create → "Worker"
 *   2. Paste this file's contents into the editor
 *   3. Settings → Variables → Add three variables:
 *        MAILCHIMP_API_KEY   (encrypt / secret)  e.g. abc123…-us21
 *        MAILCHIMP_LIST_ID   (plain)             your audience ID
 *        ALLOWED_ORIGIN      (plain)             https://whiteboard.tuneindigo.com
 *      For local dev, also allow http://localhost:8080 — see comment below.
 *   4. Save and Deploy
 *   5. Copy the deployed URL (something.workers.dev) and paste it into
 *      lib/services/signup_service.dart in place of "REPLACE-ME".
 *   6. Optional: bind the Worker to a custom domain (e.g.
 *      signup.tuneindigo.com) under Settings → Triggers → Custom Domains.
 */

export default {
  async fetch(request, env) {
    const cors = corsHeaders(request, env);

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: cors });
    }
    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405, headers: cors });
    }

    let payload;
    try {
      payload = await request.json();
    } catch {
      return json({ error: 'invalid_json' }, 400, cors);
    }

    const email = (payload.email || '').trim();
    if (!email || !/^.+@.+\..+$/.test(email)) {
      return json({ error: 'invalid_email' }, 400, cors);
    }

    if (!env.MAILCHIMP_API_KEY || !env.MAILCHIMP_LIST_ID) {
      return json({ error: 'server_misconfigured' }, 500, cors);
    }

    // Mailchimp API key format: <token>-<datacenter>, e.g. abc...-us21
    const datacenter = env.MAILCHIMP_API_KEY.split('-').pop();
    const url = `https://${datacenter}.api.mailchimp.com/3.0/lists/${env.MAILCHIMP_LIST_ID}/members`;
    const auth = 'Basic ' + btoa(`anystring:${env.MAILCHIMP_API_KEY}`);

    const mcRes = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: auth,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email_address: email,
        status: 'subscribed',
        tags: Array.isArray(payload.tags) && payload.tags.length
          ? payload.tags
          : ['whiteboard lead'],
      }),
    });

    if (mcRes.ok) {
      return json({ success: true }, 200, cors);
    }

    const mcError = await mcRes.json().catch(() => ({}));
    // "Member Exists" — already subscribed. From the user's perspective this
    // is a success: they're on the list. Front-end can tell from the message
    // field.
    if (mcError.title === 'Member Exists') {
      return json({ success: true, message: 'already_subscribed' }, 200, cors);
    }
    return json(
      { success: false, error: mcError.title || 'unknown' },
      mcRes.status || 500,
      cors,
    );
  },
};

/** Build the CORS header set. Supports a comma-separated allow-list in
 *  ALLOWED_ORIGIN (e.g. "https://whiteboard.tuneindigo.com,http://localhost:8080")
 *  so the same Worker can serve prod and local development. */
function corsHeaders(request, env) {
  const allowList = (env.ALLOWED_ORIGIN || '*')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const origin = request.headers.get('Origin') || '';
  const allowed = allowList.includes('*') || allowList.includes(origin)
    ? (allowList.includes('*') ? '*' : origin)
    : allowList[0];
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    Vary: 'Origin',
  };
}

function json(body, status, cors) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...cors },
  });
}

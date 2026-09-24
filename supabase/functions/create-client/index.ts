import { createClient } from 'npm:@supabase/supabase-js@2.116.0';
import { corsHeaders } from 'npm:@supabase/supabase-js@2.116.0/cors';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const STRONG_PASSWORD_PATTERN = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{12,128}$/;

class RequestError extends Error {
  constructor(public code: string, public status: number) {
    super(code);
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return Response.json(body, {
    status,
    headers: {
      ...corsHeaders,
      'Cache-Control': 'no-store',
    },
  });
}

function readInput(value: unknown) {
  if (!value || typeof value !== 'object') throw new RequestError('INVALID_INPUT', 400);
  const input = value as Record<string, unknown>;
  const name = typeof input.name === 'string' ? input.name.trim() : '';
  const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : '';
  const password = typeof input.password === 'string' ? input.password : '';

  if (!name || name.length > 120 || !EMAIL_PATTERN.test(email) || email.length > 254 || !STRONG_PASSWORD_PATTERN.test(password)) {
    throw new RequestError('INVALID_INPUT', 400);
  }

  return { name, email, password };
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ code: 'METHOD_NOT_ALLOWED' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authorization = request.headers.get('Authorization');

  if (!supabaseUrl || !serviceRoleKey) {
    console.error('create-client is missing required Supabase environment variables.');
    return jsonResponse({ code: 'SERVER_CONFIGURATION' }, 500);
  }

  if (!authorization?.startsWith('Bearer ')) return jsonResponse({ code: 'UNAUTHORIZED' }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let createdUserId = '';
  let createdClientId = '';

  try {
    // Verify the bearer token with Auth, then authorize against the database role.
    // Gateway JWT validation alone proves identity but does not prove admin access.
    const token = authorization.slice('Bearer '.length);
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) throw new RequestError('UNAUTHORIZED', 401);

    const { data: profile, error: profileError } = await admin
      .from('profiles')
      .select('role')
      .eq('id', userData.user.id)
      .single();
    if (profileError || profile?.role !== 'admin') throw new RequestError('FORBIDDEN', 403);

    const input = readInput(await request.json());
    const { data: existingClient, error: existingClientError } = await admin
      .from('clients')
      .select('id')
      .eq('contact_email', input.email)
      .maybeSingle();
    if (existingClientError) throw existingClientError;
    if (existingClient) throw new RequestError('EMAIL_EXISTS', 409);

    const { data: authData, error: authError } = await admin.auth.admin.createUser({
      email: input.email,
      password: input.password,
      email_confirm: true,
      user_metadata: { full_name: input.name },
    });
    if (authError) {
      if (authError.status === 422 || authError.message.toLowerCase().includes('already')) {
        throw new RequestError('EMAIL_EXISTS', 409);
      }
      throw authError;
    }

    createdUserId = authData.user.id;

    const { data: client, error: clientError } = await admin
      .from('clients')
      .insert({ name: input.name, contact_name: input.name, contact_email: input.email })
      .select('id, name')
      .single();
    if (clientError) throw clientError;

    createdClientId = client.id;
    const { error: linkError } = await admin
      .from('client_users')
      .insert({ client_id: client.id, user_id: createdUserId });
    if (linkError) throw linkError;

    return jsonResponse({ client }, 201);
  } catch (error) {
    // Auth user creation and Postgres inserts cannot share one transaction. If a
    // later step fails, remove earlier records so the next retry starts cleanly.
    if (createdClientId) {
      const { error: cleanupClientError } = await admin.from('clients').delete().eq('id', createdClientId);
      if (cleanupClientError) console.error('create-client client cleanup failed:', cleanupClientError.code);
    }
    if (createdUserId) {
      const { error: cleanupUserError } = await admin.auth.admin.deleteUser(createdUserId);
      if (cleanupUserError) console.error('create-client user cleanup failed:', cleanupUserError.status);
    }

    if (error instanceof RequestError) return jsonResponse({ code: error.code }, error.status);
    console.error('create-client failed:', error instanceof Error ? error.message : 'unknown error');
    return jsonResponse({ code: 'CLIENT_CREATE_FAILED' }, 500);
  }
});

# Client Project Portal — Stage 2: Frontend Implementation

## Objective

Design and implement the frontend for the Client Project Portal using React, Vite, and Vanilla CSS. The frontend will connect to the Supabase backend established in Stage 1 and provide a premium, modern user experience for both the administrator (you) and the clients.

---

## Architectural Decisions

### 1. Technology Stack
- **Framework**: React via Vite (`npm create vite@latest . -- --template react`)
- **Routing**: `react-router-dom` for handling Login, Admin, and Client routes.
- **Backend Connection**: `@supabase/supabase-js` for authentication and database queries.
- **Styling**: **Vanilla CSS**. We will build a robust design system with modern aesthetics (glassmorphism, vibrant but professional colors, smooth micro-animations). *Note: Per guidelines, TailwindCSS will not be used.*
- **State Management**: React Context for global Auth state, and custom hooks for fetching Supabase data.

### 2. Design Aesthetics & UI/UX
- **Theme**: A sleek, premium dark/light mode setup, utilizing deep backgrounds (e.g., `#0f172a`), subtle gradients, and glassmorphic panels for cards.
- **Typography**: Modern sans-serif fonts (like `Inter` or `Outfit`) imported via Google Fonts.
- **Micro-interactions**: Hover effects on buttons, smooth page transitions, and skeleton loaders for data fetching to ensure the app feels dynamic and alive.

### 3. Authentication Flow
- **Login Only**: A single login screen for both Admin and Clients.
- **No Sign Up**: As decided, accounts are created manually. There will be no "Register" link.
- **Role-based Routing**: After successful login, the app checks the user's role in the `profiles` table:
  - If `role === 'admin'`, redirect to `/admin`.
  - If `role === 'client'`, redirect to `/portal`.

---

## Proposed Changes

### 1. Project Initialization & Setup
- Initialize Vite React project in the current directory.
- Install dependencies (`@supabase/supabase-js`, `react-router-dom`, `lucide-react` for icons).
- Set up environment variables (`.env`) for `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.

### 2. Core Structure & Routing
Create the following route structure:
- `/` - Redirects to `/login` if unauthenticated, or to the respective dashboard if authenticated.
- `/login` - Minimalist, beautiful login form.
- `/admin/*` - Protected routes for the Admin:
  - `/admin` (Overview of all clients and active projects)
  - `/admin/project/:id` (Manage phases, updates, payments, comments)
- `/portal/*` - Protected routes for the Client:
  - `/portal` (Client's active project overview, timeline, payments, comments)

### 3. State Management & Supabase Client
- **`src/lib/supabase.js`**: Initialize the Supabase client.
- **`src/contexts/AuthContext.jsx`**: Provide the current user session and profile data (including role) to the rest of the app.
- **`src/hooks/`**: Custom hooks (e.g., `useProjects`, `usePhases`, `useComments`) to encapsulate data fetching and real-time subscriptions if necessary.

### 4. Component Library (Vanilla CSS)
Establish a design system in `src/index.css` with CSS variables for colors, spacing, and typography.
Build reusable UI components:
- `Button`: Primary, secondary, danger variants with hover animations.
- `Card`: Glassmorphic containers for project phases and updates.
- `Badge`: Status indicators (e.g., "Active", "Completed").
- `ProgressBar`: Animated progress bar for project completion.
- `Input` / `Textarea`: Styled form controls.

### 5. Feature Implementation
#### Admin Dashboard
- View all clients and projects.
- Update project progress.
- Add new project phases.
- Add project updates.
- Add comments (immutable once posted, as requested).

#### Client Portal
- View project status, progress bar, and active phase.
- View a timeline of project phases and updates.
- View payment status.
- Add comments to communicate with the Admin.

---

## Open Questions

> [!IMPORTANT]
> **Design Preferences**: Do you have a specific color palette in mind for the portal, or should I proceed with a modern, sleek dark theme with vibrant accents (e.g., deep blue/slate with neon blue/purple accents)?

> [!IMPORTANT]
> **Real-time Updates**: Do you want the frontend to listen to Supabase real-time subscriptions (e.g., if you post an update, the client sees it immediately without refreshing the page)? Or is standard data fetching on page load sufficient for the MVP?

> [!IMPORTANT]
> **File Structure**: Should I initialize the Vite project directly in the `client_portal` directory (so that `package.json` is at the root alongside `supabase/`), or would you prefer a separate `frontend/` folder inside `client_portal`?

---

## Verification Plan

### Automated Tests
- No automated frontend testing (Jest/Cypress) is planned for this MVP unless requested.

### Manual Verification
1. Run `npm run dev` to start the Vite server.
2. Verify the design aesthetics meet the "premium and dynamic" requirements.
3. Login as Admin: Ensure access to the admin dashboard and ability to view/edit projects.
4. Login as Client: Ensure access ONLY to the client portal and proper data isolation (cannot see other clients' data).
5. Test adding a comment from both sides to ensure RLS policies function correctly through the UI.

-- ============================================================
-- 00_enums.sql
-- Custom ENUM types for the Client Project Portal
-- ============================================================
-- These provide type safety at the database level.
-- PostgreSQL enforces that only valid values can be stored.
-- To add a new value later: ALTER TYPE <name> ADD VALUE 'new_value';
-- ============================================================

-- User roles: determines authorization level
CREATE TYPE user_role AS ENUM ('admin', 'client');

-- Project lifecycle states
CREATE TYPE project_status AS ENUM (
  'planned',
  'active',
  'paused',
  'completed',
  'cancelled'
);

-- Phase progression states
CREATE TYPE phase_status AS ENUM (
  'pending',
  'active',
  'completed'
);

-- Payment tracking states (display only, no real transactions)
CREATE TYPE payment_status AS ENUM (
  'pending',
  'paid',
  'overdue',
  'cancelled'
);

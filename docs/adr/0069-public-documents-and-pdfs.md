# ADR-0069: Public documents and policies as PDFs, rebuilt from their pages

- **Status:** Accepted
- **Date:** 2026-10-24
- **Sub-phase:** P14.3d
- **Code:** `core/catalog/documents.jac`, `core/catalog/policies.jac` (`upload_policy_pdf`, `remove_policy_pdf`, `public_policy_pdf`), `core/theming/branding_api.jac` (`documents`), `web/backoffice/DocumentsSection.jac`, `web/backoffice/PoliciesSection.jac`, `web/storefront/DocumentPage.jac`, `web/storefront/PolicyPage.jac`, `web/storefront/FooterInfo.jac`, `jac.toml` (pypdf)
- **Tests:** `tests/unit/documents_tests.jac`, `tests/integration/documents_tests.jac`, `tests/isolation/registry.jac`, `e2e/documents_tests.jac`

## Context
Cinemas want to show visitors their KFCB film exhibition licence, county business permit and the snack counter's health certificate. Some have their policies as PDFs from a lawyer. A PDF can carry scripts, open actions, attached files, forms and links, so we can't serve one as it was uploaded.

## Decision
1. **Every PDF is rebuilt from its pages alone,** as we re-encode every image.
   - **The library:** we added `pypdf`, a pure-Python library.
   - **What's accepted:** an upload must be at most 10 MB (checked before decoding) and start with `%PDF-`. pypdf must be able to read it, it can't have a password, and it can have at most 50 pages.
   - **What's rebuilt:** its pages are copied into a new file, with their annotations and page actions removed. Nothing at the document level comes across: no scripts, open actions, attachments, forms or metadata.
   - **Where it's stored:** the new file goes under a random name in the cinema's media folder.
   - **Refusals:** a refused file says why: not a readable PDF, password-protected, too many pages, or too large.
2. **Public documents.** Up to 10 per cinema, each a title and a PDF, kept on a `PublicDocuments` node owned by the cinema.
   - **Managing them:** Settings → Documents, by staff who change the cinema's settings. The title field suggests the three usual documents. Each upload and removal is audited.
   - **On the storefront:** every footer links to each document, and its page (`/documents/<id>`) opens the PDF.
3. **A policy may be a PDF.** It's uploaded in the policy's editor and shown on the policy's page above any text.
   - **Publishing:** a policy can be published with text, with a PDF, or with both.
   - **Removing:** a PDF can't be removed while it's the only content of a published policy.
4. **Opening a PDF.** The server sends it as base64 (as posters are sent), and the page makes a local blob URL.
   - **Open the PDF** is a plain link to it in a new tab, so no popup blocker stops it. **Download** saves it.
   - Phones open it in their own viewer.
   - Jac doesn't document a way for a function to answer with raw bytes and a content type, so there's no direct file URL.

## Consequences
- **Visible content stays.** Rebuilding removes clickable links in a PDF; the visible text stays.
- **No hidden PDF content.** A PDF whose content needs scripts or forms won't work, and documents for visitors shouldn't need them.
- **Size.** Large PDFs travel as base64 inside JSON, about a third bigger. 10 MB is the limit.
- **Private documents are different.** Verification documents (14.4) are private, never in the footer, and have their own storage and retention decision.

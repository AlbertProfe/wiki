# PRA01: Creating a React + Vite SPA frontend for ApartmentPredictor (CRUD & conditional rendering)

## 24/CIFOCS_ED/707/0189722/002 - IFCD0210 Desenvolupament d’aplicacions amb tecnologies web

<mark>CIFO La Violeta - Web App Developer Certification</mark>

- doc version: `v1` (2026 edition)

In this practical exercise, you will create from scratch (or strongly build upon the provided stub) a **React Single Page Application (SPA)** using **Vite** as the build tool. The frontend will serve as the user interface for the **ApartmentPredictor** project, displaying and managing a list of apartments with full **CRUD** functionality (Create, Read, Update, Delete) using **conditional rendering** techniques.

Instead of connecting to a real backend API at this stage, you will **consume static data** from a `/data` folder containing a JavaScript/TypeScript file that exports an array of apartment objects (mock data simulating what the Spring Boot backend would return).

<mark>You'll design, implement, test and document a modern React SPA</mark> with Vite, using functional components, hooks, conditional rendering, list rendering, and basic form handling — all aligned with UF1841, UF1842 and UF1843 competencies.

## Objectives

> Create a Vite + React project from scratch (or extend the stub), implement a static data layer in `/data`, build a SPA with apartment listing + CRUD operations using conditional rendering, and document the process with screenshots and explanations.

### Project Base

- Backend reference (for understanding data shape): [GitHub - AlbertProfe/ApartmentPredictor](https://github.com/AlbertProfe/ApartmentPredictor)
- Frontend stub to start from / extend: [GitHub - AlbertProfe/ApartmentPredictor-React](https://github.com/AlbertProfe/ApartmentPredictor-React)
- Official Course: [IFCD0210 materials & deliveries](https://albertprofe.dev/ifcd0021-1-25/ifcd0021-1-25.html) (adapted to 2026 edition)
- Vite Documentation: [vite.dev](https://vite.dev)
- React Documentation: [react.dev](https://react.dev) — especially "Describing the UI" and "Managing State"
- Modern React recommended practices: [beta.reactjs.org → react.dev](https://react.dev/learn)

### Tasks

Summary tasks:

- [ ] Create project with Vite + React (PRA01)
- [ ] Create `/data/apartments.js` or `/data/apartments.ts` with sample array
- [ ] Implement main views: List, Detail, Create/Edit form with conditional rendering
- [ ] CRUD logic using useState + local mock data
- [ ] Basic layout & responsive styling (Tailwind / CSS modules / plain CSS)
- [ ] Add README.md documentation + screenshots
- [ ] Chose **one option** from tasks 4, 5 and 6. If nay of this fits for now, propose a 4th option.
- [ ] Write basic tests with Vitest (optional but recommended)

Detailed tasks:

1. **Initialize or extend the React + Vite project**
   
   - Option A: Create a **new project** using Vite:
     
     ```bash
     npm create vite@latest apartment-predictor-frontend -- --template react-ts
     cd apartment-predictor-frontend
     npm install
     ```
   
   - Option B: Clone/extend the provided stub repository [ApartmentPredictor-React](https://github.com/AlbertProfe/ApartmentPredictor-React) and upgrade it to latest Vite + React 18/19 patterns.
   
   - Option C: Clone/extend the provided stub repository [ApartmentPredictor-React](https://github.com/AlbertProfe/ApartmentPredictor-React) and do not upgrade, remove `axios` `useEffect`

2. **Create static data layer (/data/apartments.js or .ts)**
   
   - Create folder `/src/data/`
   
   - Add file `apartments.js` with the Array of Literal `Apartments` 
     
     - Create the data using the sever backend Java Spring Boot or use another options (you can use AI).
     
     - (Optional) Add file `apartments.ts` (recommended) or `apartments.js`
     
     - (Optional) Export an array of literal objects representing apartments. Example structure:
       
       ```ts
       // src/data/apartments.ts
       export interface Apartment {
         id: string;
         title: string;
         price: number;
         rooms: number;
         bathrooms: number;
         surface: number;
         location: string;
         description?: string;
         imageUrl?: string;
         interested?: boolean;
         createdAt: string;
       }
       
       export const initialApartments: Apartment[] = [
         {
           id: "apt-001",
           title: "Bright flat in Eixample",
           price: 1250,
           rooms: 3,
           bathrooms: 1,
           surface: 85,
           location: "Barcelona, Eixample Dreta",
           description: "Recently renovated, elevator, balcony.",
           imageUrl: "https://images.unsplash.com/photo-...",
           interested: false,
           createdAt: "2026-01-15T10:30:00Z"
         },
         // add 4–8 more realistic entries
       ];
       ```

3. **Build the SPA views & CRUD functionality**
   
   - Use **conditional rendering** to switch between:
     - Apartment list (`<ApartmentList />`)
     - Apartment detail view (`<ApartmentDetail />`)
     - Create / Edit form (`<ApartmentForm />`)
   - Main layout suggestion: header + sidebar (filters) + main content area
   - Implement:
     - List all apartments (map + key)
     - Click → show detail (conditional: selectedId !== null)
     - Add new apartment (form)
     - Edit existing (pre-fill form)
     - Delete (confirm + remove from state)
   - Manage state with `useState<Apartment[]>` and `useState<Apartment | null>` for selected/editing item

4. **Styling & UX** (`optional 1`)
   
   - Use **Tailwind CSS** (recommended — install via `npm install -D tailwindcss postcss autoprefixer` + init) or plain CSS / CSS modules
     - You can chose another CSS framework: Material UI, etc..
   - Responsive grid for cards
   - Use icons (e.g. Lucide-React, Heroicons)
   - Show loading / empty states

5. **Extend model and UI with Reviews array** (`optional 2`)
   
   - Add the reviews: Review[] field to the Apartment interface (as shown in task 2)
   - In the **detail view** (<ApartmentDetail />):
     - Display all reviews in a list or accordion
     - Show average rating (calculated from reviews)
     - Display number of reviews
   - In the **edit/create form** (optional but recommended for full CRUD practice):
     - Allow adding one new review when creating/editing an apartment (simple form: author, rating 1–5, comment)
     - Append the new review to the reviews array when saving
   - Ensure reviews are preserved during CRUD operations (they travel with the apartment object in state)

6. **Connect the React frontend to the Spring Boot backend using Axios** (`optional 3`)
   
   - This task transitions the ApartmentPredictor SPA from static mock data to real backend integration using **Axios**. 
   - Students first install Axios (`npm install axios`) and create a dedicated service module (`/src/services/apartmentService.ts`) that centralizes API calls with a configurable base URL pulled from environment variables (`VITE_API_BASE_URL`). 
   - The service defines typed async functions for full CRUD: `getAllApartments`, `getApartmentById`, `createApartment`, `updateApartment`, `deleteApartment`, and an optional `addReview` endpoint.

7. **Documentation & delivery**
   
   - Update `/docs/PRA01.md` with:
     - Explanation of conditional rendering decisions
     - How you modeled the Apartment type
     - Main challenges & solutions
   - Add `/docs/images/` with screenshots:
     - List view
     - Detail view
     - Create/Edit form
     - Mobile view (responsive)

8. **Optional extension (if time allows)**
   
   - Add simple filters (price range, rooms)
   - Persist data in `localStorage`
   - Add Vitest unit tests for components

### Submission Guidelines

1. Create folder `IFCD0210-2026-PRA01-YourName` (e.g. `IFCD0210-2026-PRA01-MarcPalau`)
2. Inside it:
   - `/apartment-predictor-frontend` ← your React+Vite project
   - `/docs` ← documentation
     - `PRA01.md` (this file updated + your explanations)
     - `/images/` ← screenshots
3. Initialize git → commit often → push to your personal GitHub
4. Create **zip** of the whole folder
5. Submit zip via the delivery platform: [IFCD0210 Deliveries 2026](https://albertprofe.dev/...) (link to be confirmed)

### Evaluation Criteria

- Correct Vite + React project creation / extension
- Proper modeling of Apartment data in `/data`
- Effective use of **conditional rendering** for views (list ↔ detail ↔ form)
- Clean CRUD implementation using React hooks
- Responsive & clean UI (bonus: Tailwind/Material/...)
- Quality README + documentation in `/docs`
- Screenshots demonstrating functionality
- Overall code organization, naming, and modern React practices

Good luck — build a clean, modern SPA!

Focus on **conditional rendering**, **component composition**, and **state management** — core topics of UF1842 & UF1843.

# PRA#02: Java UML + Implementation + H2 Data Population

- [Project Repository](https://github.com/AlbertProfe/ApartmentPredictor)
- `v_1.0`

## Summary

> This laboratory reinforces **object-oriented modeling** and **Java implementation** skills while introducing basic **server-side persistence** concepts within the **MF0492_3 Programació web en l’entorn servidor** module.  
> 
> Students will extend the apartment predictor domain model by designing an enhanced UML class diagram, implementing new classes and relationships, and — in a single well-structured commit — populating an **H2 in-memory database** (or local, if prefer) with realistic fake data using **Spring Boot**, **Spring Data JPA**, and a data initializer/loader.  
> 
> The exercise emphasizes **multi-level inheritance**, **composition/aggregation**, **JPA entity mapping**, **repository usage**, and **CommandLineRunner / @Component** populator data seeding techniques.

## Reference Commit d4c9885

Reference commit <mark>d4c9885</mark> that populates the database in one go:  

- [Project Repository with pseudocode: d4c9885](https://github.com/AlbertProfe/ApartmentPredictor/commits/6e8f316459d6308cec627dc77a7f21e74815841e/)

Students should aim for a similar clean, atomic commit that adds entities, repositories, and fake data initialization logic.

Other references:

- [ApartmentPredictor/docs/PRA/Lab#01_Java_SE_Inheritance.md at master · AlbertProfe/ApartmentPredictor · GitHub](https://github.com/AlbertProfe/ApartmentPredictor/blob/master/docs/PRA/Lab%2301_Java_SE_Inheritance.md)

- [ApartmentPredictor/docs/appends/JPA_RelationshipsImplementation_Rule.md at master · AlbertProfe/ApartmentPredictor · GitHub](https://github.com/AlbertProfe/ApartmentPredictor/blob/master/docs/appends/JPA_RelationshipsImplementation_Rule.md)

- [ApartmentPredictor/docs/appends/JPA_Relationships_Guide.md at master · AlbertProfe/ApartmentPredictor · GitHub](https://github.com/AlbertProfe/ApartmentPredictor/blob/master/docs/appends/JPA_Relationships_Guide.md)

- [Spring Boot: Dependency Injection](https://albertprofe.dev/springboot/boot-concepts-injection.html) / [Spring Boot: JPA Inherence](https://albertprofe.dev/springboot/boot-concepts-jpa-5.html)

## Inherence storing at H2 DB

**Inheritance Strategy Decision**

> In JPA, when designing an inheritance hierarchy (such as `Person → Owner, Reviewer` or `Property → Apartment, House, Townhouse`), you must choose an inheritance mapping strategy. 

For this lab you will select **exactly one** of the two following strategies and justify your choice in the documentation (`/docs/LAB02.md`).

**Option A – @MappedSuperclass**  

- https://albertprofe.dev/images/springboot/inherence-jpa-mapped-superclass.png

Use `@MappedSuperclass` on the parent class (e.g. `Person` or `ResidentialProperty`).  
This strategy:  

- Does **not** create a table for the superclass  
- Shares common fields/mappings (getters, annotations like `@Column`, `@Temporal`) among all subclasses  
- Each concrete subclass gets its **own independent table** containing both inherited + specific fields  
- Advantages: simple queries, no JOINs needed, clean schema  
- Disadvantages: duplicated columns across tables, no polymorphic queries on superclass type  

**Option B – TABLE_PER_CLASS (InheritanceType.TABLE_PER_CLASS)**  

- [Spring Boot: JPA Inherence – albertprofe wiki](https://albertprofe.dev/springboot/boot-concepts-jpa-5.html#table_per_class)

Use `@Inheritance(strategy = InheritanceType.TABLE_PER_CLASS)` on the abstract/root entity.  
This strategy:  

- Creates a **separate table for each concrete class**  
- Each table contains **all fields** (inherited + own)  
- Allows polymorphic queries and references to the superclass type  
- Advantages: full polymorphism support, clean OO design  
- Disadvantages: poor performance with deep hierarchies (UNION queries), difficult schema evolution, not recommended by most teams for large systems  

## Tasks

Starting point:

- From commit <mark>d4c9885</mark> follow the path craeted by the pseudocode.

Objectives

- Practice domain modeling with **UML** and **multi-level inheritance** 
- Correctly map entities using **JPA annotations** (`@Entity`, `@Id`, `@GeneratedValue`, `@Inheritance`, `@ManyToOne`, etc.) 
- Seed an **H2 database** with realistic fake data using `CommandLineRunner` or `DataLoader` choosing the right approach.
- Implement **Spring Data JPA repositories** 
- Create **REST controllers** with basic CRUD 
- @Service is no need for this version but we value it.
- Verify functionality via **Postman** collections

Summary tasks

- [ ] Define & write the **Product Goal** 
- [ ] Create / update the **UML class diagram** (mermaid) 
- [ ] Implement **all entities** with proper JPA + inheritance (`Person` hierarchy) 
- [ ] Create **Spring Data JPA repositories** 
- [ ] Populate **H2 DB** with fake data (one atomic step/commit) 
- [ ] Implement **@RestController** classes with CRUD endpoints 
- [ ] Test endpoints with **Postman** (export collection) 
- [ ] Document decisions, UML, screenshots (H2 console + Postman)

Detailed tasks

1. **Define and document the Product Goal**
- Write 1–2 clear paragraphs explaining the business & technical purpose of this backend module 

- Place it in `README.md` or `/docs/LAB02.md` at the top 

- Example aspects to cover: supported property types, users/owners, future frontend integration, why inheritance, value of pre-populated data
2. **Create / enhance the UML class diagram**
- Use **mermaid** syntax (place in README or `/docs/LAB02-uml.md`) 
3. **Implement all entities with JPA & inheritance**
- Use `@Entity`, `@Id`, `@GeneratedValue(strategy = GenerationType.IDENTITY)` or `UUID` as you prefer
  
  - Implement **inheritance** for `Person` → at least two subclasses (`Owner`, `Reviewer`)
  - Example: `Person` with `id`, `fullName`, `email`, `phone`
  - Use `@ManyToOne`, `@OneToMany`, `@ElementCollection` where appropriate
4. **Create Spring Data JPA repositories**
- At minimum: `ReviewerRepository`, `OwnerRepository`, `PersonRepository` (if useful)
  
  - Optional: custom queries with `@Query` (e.g. find by price range, by city)
5. **Populate H2 database with fake data**
- Create `@Component` class implementing `CommandLineRunner`
  
  - In `run()` method:
  - Create 3–5 `Owner` / `Agent` instances
  - Create 10–20 properties of different types (`Apartment`, `House`, `Townhouse`)
  - Link owners to properties
  - Use builders or constructors with realistic Spanish/Catalan addresses, prices, etc.
  - Make this population **idempotent** or clean previous data (`deleteAll()` in dev)
  - Commit this logic in one clean, well-commented commit

- Use a populatro as orchestrator as the commit with pseudocode signs.
6. **Implement REST Controllers**
- Create `@RestController` classes, e.g.:
  
  - `OwnerController` → GET /api/properties, GET /api/owner/{id}, POST, PUT, DELETE
  - `OwnerController` → similar CRUD
  - Use `@Autowired` repositories
  - Return `ResponseEntity` with proper HTTP status codes
  - Optional: add `@CrossOrigin` for future React frontend
7. **Test with Postman**
- Create a **Postman collection** named `ApartmentPredictor Backend 2026` or similar and publish it.
  
  - Include requests for:
  - GET all owners
  - GET one owner
  - POST new apartment
  - PUT update
  - DELETE
  - GET all owners
  - Export the collection as `.json` and include in `/docs/postman/`
  - Take screenshots of successful responses
8. **Documentation & delivery**
- Update `/docs/LAB02.md`:
  - Your Product Goal
  - Explanation of inheritance choice & JPA strategy
  - Challenges & solutions (e.g. discriminator, cascading, data population logic)
  - Add `/docs/images/`:
  - UML diagram screenshot
  - H2 console tables populated
  - Postman requests + responses (at least 4–5)

## Data Initialization Pattern

Appraoch with **CommandLineRunner**

```java
@Component
public class DataInitializer implements CommandLineRunner {

    private final ApartmentRepository apartmentRepo;
    private final HouseRepository houseRepo;
    private final OwnerRepository ownerRepo;
    // ...

    @Override
    public void run(String... args) throws Exception {
        // Clear previous data (optional in dev)
        apartmentRepo.deleteAll();

        Owner owner1 = new Owner("Maria Soler", "maria@example.com", "654321098");
        ownerRepo.save(owner1);

        Apartment apt1 = Apartment.builder()
            .address("Carrer Major 45, Barcelona")
```

Approach with **Populate with API Rest Controller**

![](https://raw.githubusercontent.com/AlbertProfe/ApartmentPredictor/refs/heads/master/docs/screenshots/code-populatedb.png)

## Submission Guidelines

1. Create a clearly named delivery folder  
   `IFCD0210-2026-LAB02-YourName`  
   (example: `IFCD0210-2026-LAB02-MarcPalau`)

2. Inside the folder organize your work as follows:
   
   - `/apartment-predictor-backend`  
     ← your complete Spring Boot project (either created from scratch, extended from the reference repository, or cleanly rebased)
   
   - `/docs` ← all documentation artifacts  
     
     - `LAB02.md`  
       (this file updated with your Product Goal, inheritance strategy decision (~200 words), UML explanation, JPA choices, challenges & solutions)  
     - `/images/` ← screenshots (required & recommended):  
       - Mermaid UML diagram (rendered or exported)  
       - H2 console showing populated tables (at least `APARTMENT`, `PERSON`/`OWNER`, and any relationship table)  
       - Postman collection runner results or individual request/response pairs (minimum 5 meaningful calls: GET all, GET one, POST, PUT, DELETE)  
       - (optional) IntelliJ / VS Code structure or entity class diagram view

3. Initialize a git repository inside `/apartment-predictor-backend` (if not already done)  
   → commit logically and frequently  
   → push the project to your **personal public  GitHub repository**  
   → include the repository URL in `LAB02.md`

4. Create a **zip archive** of the entire `IFCD0210-2026-LAB02-YourName` folder  
   (ensure the zip contains both the backend source code and the `/docs` folder)

5. Submit the zip file via the official delivery platform:  
   **IFCD0210 Deliveries 2026**  
   (link to be confirmed by the instructor — check the course space or announcement)

**Important notes**  

- Do **not** include `target/`, `.idea/`, `*.log`, or any build artifacts in the zip or git repository  
- Make sure the project runs out-of-the-box with `mvn spring-boot:run` (H2 in-memory, data population on startup, H2 console enabled)  
- Include the Postman collection **inside** `/docs/postman/` as a `.json` file (export → Collection v2.1 format recommended)

## Evaluation Criteria

- Clear, realistic and well-written **Product Goal** (business + technical purpose)
- Expressive and correct **UML class diagram** (mermaid syntax, showing inheritance + associations)
- Conscious and justified choice of **JPA inheritance strategy** (@MappedSuperclass **or** TABLE_PER_CLASS) with 150–200 word reasoning
- Correct and clean **JPA entity implementation** (annotations, inheritance mapping, relationships, field types, naming conventions)
- Realistic and reasonably sized **H2 database population** (~10–20+ APARTMENTS + owners/reviewrs, meaningful values, no trivial/test data)
- Functional and well-structured **Spring Data JPA repositories** (at least 2–3, optional custom queries = bonus)
- Complete and RESTful **@RestController** implementation (full CRUD on key entities, proper ResponseEntity usage, HTTP status codes)
- High-quality **Postman collection** with representative requests/responses (exported .json + screenshots)
- Clear, structured documentation in `LAB02.md` (decisions, challenges, solutions)
- Visual evidence in `/docs/images/` (UML, H2 console, Postman)
- Overall backend code quality: package structure, naming, separation of concerns, modern Spring Boot practices
- Bonus points:  
  - Custom `@Query` methods  
  - Basic input validation (`@Valid`, Bean Validation)  
  - Exception handling / `@ControllerAdvice`  
  - Lombok usage (judiciously)  
  - README with quick-start instructions

Focus your effort on producing a **solid, production-like backend foundation** — clean modeling, persistence reliability, and testable REST API — ready to connect to the React SPA from PRA01.

## Deliverables

1. Fork & clone your personal repository
2. Work on branch `lab02-yourGitHubUsername`
3. Commit your UML updates, new classes, repositories, configuration, and **data initializer** in **one well-described commit** (or a very small number of clean commits)
4. Push changes
5. Open a **Pull Request** to the original repository’s `main`/`master`
6. In the PR description include:
   - Link to your updated mermaid UML diagram
   - Brief explanation of new entities / associations added
   - Screenshot of H2 console showing populated tables
   - Output of `SELECT * FROM PROPERTY` or similar (or screenshot)
   - Any interesting decisions / challenges

Good luck — this lab bridges **Lab#01_Java_SE_Inheritance** and **server-side persistence** — core skills for **MF0492_3 Programació web en l’entorn servidor** and completes the  **PRA01: Creating a React + Vite SPA frontend for ApartmentPredictor (CRUD & conditional rendering)**

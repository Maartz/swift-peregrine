# Build a Todo App with Peregrine

Learn the fundamentals of Peregrine by building a full-featured todo list application with a JSON API, HTML views, validations, and authentication.

**What you'll build:**

- A JSON API for managing todos (`GET`, `POST`, `PUT`, `DELETE`)
- Server-rendered HTML pages with ESW templates
- Input validation with changesets
- Session-based authentication with protected routes

**Prerequisites:**

- Swift 6.0+ and macOS 14+
- PostgreSQL running locally
- Basic familiarity with Swift

---

## 1. Create the Project

Use the Peregrine CLI to scaffold a new app:

```bash
peregrine new TodoApp
cd TodoApp
```

This generates:

```
TodoApp/
  Package.swift
  Sources/
    TodoApp/
      App.swift
      Views/
        layout.esw
  .gitignore
  .swift-format
```

Open `Package.swift` to see the dependencies wired up automatically:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TodoApp",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/Maartz/swift-peregrine", from: "1.0.0"),
        .package(url: "https://github.com/Spectro-ORM/ESW.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "TodoApp",
            dependencies: [
                .product(name: "Peregrine", package: "swift-peregrine"),
            ],
            plugins: [
                .plugin(name: "ESWBuildPlugin", package: "ESW"),
            ]
        ),
    ]
)
```

Create the database:

```bash
createdb todo_app_dev
```

---

## 2. Define the Todo Model

Create `Sources/TodoApp/Models/Todo.swift`:

```swift
import Peregrine

@Schema("todos")
struct Todo {
    @ID var id: UUID
    @Column var title: String
    @Column var body: String?
    @Column var completed: Bool
    @Column var position: Int
    @Timestamp var createdAt: Date
    @Timestamp var updatedAt: Date
}
```

The `@Schema` macro maps the struct to a `todos` database table. `@ID` generates a UUID primary key, `@Column` maps properties to columns, and `@Timestamp` auto-sets `NOW()` on insert.

---

## 3. Write the Migration

Create `Sources/Migrations/1_create_todos.sql`:

```sql
-- migrate:up
CREATE TABLE "todos" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "title" TEXT NOT NULL,
    "body" TEXT,
    "completed" BOOLEAN NOT NULL DEFAULT false,
    "position" INT NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- migrate:down
DROP TABLE "todos";
```

Run it:

```bash
peregrine migrate up
```

---

## 4. Build the JSON API

Let's start with a pure JSON API. Create `Sources/TodoApp/Routes/TodoAPI.swift`:

```swift
import Peregrine

@RouteBuilder
func todoAPIRoutes() -> [Route] {

    // List all todos, ordered by position
    GET("/api/todos") { conn in
        let todos = try await conn.repo().all(Todo.self)
        return try conn.json(value: todos)
    }

    // Get a single todo
    GET("/api/todos/:id") { conn in
        guard let id = conn.params["id"].flatMap(UUID.init) else {
            throw NexusHTTPError(.badRequest, message: "Invalid ID")
        }
        guard let todo = try await conn.repo().get(Todo.self, id: id) else {
            throw NexusHTTPError(.notFound, message: "Todo not found")
        }
        return try conn.json(value: todo)
    }

    // Create a new todo
    POST("/api/todos") { conn in
        let input = try conn.decode(as: CreateTodoInput.self)

        var changeset = Changeset(data: input, action: .create)
        await changeset.validate(using: [
            .required("title") { $0.title },
            .length("title", { $0.title }, min: 1, max: 200),
        ])

        let validated = try changeset.requireValid()

        var todo = Todo()
        todo.title = validated.title
        todo.body = validated.body
        todo.completed = false
        todo.position = 0

        let created = try await conn.repo().insert(todo)
        return try conn.json(status: .created, value: created)
    }

    // Update a todo
    PUT("/api/todos/:id") { conn in
        guard let id = conn.params["id"].flatMap(UUID.init) else {
            throw NexusHTTPError(.badRequest, message: "Invalid ID")
        }
        guard var todo = try await conn.repo().get(Todo.self, id: id) else {
            throw NexusHTTPError(.notFound, message: "Todo not found")
        }

        let input = try conn.decode(as: UpdateTodoInput.self)
        if let title = input.title { todo.title = title }
        if let body = input.body { todo.body = body }
        if let completed = input.completed { todo.completed = completed }
        if let position = input.position { todo.position = position }
        todo.updatedAt = Date()

        let updated = try await conn.repo().insert(todo)
        return try conn.json(value: updated)
    }

    // Delete a todo
    DELETE("/api/todos/:id") { conn in
        guard let id = conn.params["id"].flatMap(UUID.init) else {
            throw NexusHTTPError(.badRequest, message: "Invalid ID")
        }
        try await conn.repo().delete(Todo.self, id: id)
        return try conn.json(value: ["deleted": true])
    }
}

// MARK: - Input Types

struct CreateTodoInput: Decodable, Sendable {
    let title: String
    let body: String?
}

struct UpdateTodoInput: Decodable, Sendable {
    let title: String?
    let body: String?
    let completed: Bool?
    let position: Int?
}
```

Key concepts:

- **`@RouteBuilder`** lets you list routes declaratively, like SwiftUI views.
- **`conn.params["id"]`** reads route parameters (the `:id` in the path).
- **`conn.decode(as:)`** parses the JSON request body into a `Decodable` struct.
- **`conn.repo()`** gives you a Spectro repository for database queries.
- **`Changeset` + `ValidatorRule`** validates input before touching the database.
- **`conn.json(value:)`** encodes the response as JSON and halts the pipeline.

---

## 5. Wire Up the App

Open `Sources/TodoApp/App.swift` and mount the routes:

```swift
import Peregrine

@main
struct TodoApp: PeregrineApp {
    let database = Database.postgres(database: "todo_app")

    @RouteBuilder var routes: [Route] {
        todoAPIRoutes()
    }
}
```

Build and run:

```bash
swift build && .build/debug/TodoApp
# Peregrine running on http://127.0.0.1:8080
```

Test it:

```bash
# Create a todo
curl -X POST http://localhost:8080/api/todos \
  -H "Content-Type: application/json" \
  -d '{"title": "Learn Peregrine", "body": "Build a todo app"}'

# List all todos
curl http://localhost:8080/api/todos

# Toggle completed
curl -X PUT http://localhost:8080/api/todos/<ID> \
  -H "Content-Type: application/json" \
  -d '{"completed": true}'
```

---

## 6. Add HTML Views

Now let's add server-rendered pages. Peregrine uses **ESW** templates (Embedded Swift for the Web) — similar to ERB/EEx but compiled at build time for type safety.

### Layout

Your `Sources/TodoApp/Views/layout.esw` was generated by `peregrine new`. It wraps every page:

```html
<%!
var conn: Connection
var title: String
var content: String
%>
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><%= title %> — TodoApp</title>
    <link rel="stylesheet" href="/css/pico.min.css">
    <link rel="stylesheet" href="/css/app.css">
</head>
<body>
    <main class="container">
    <%- content %>
    </main>
</body>
</html>
```

The `<%! %>` block declares typed variables. `<%= %>` outputs escaped HTML. `<%- %>` outputs raw HTML (for nested templates).

### Index Page

Create `Sources/TodoApp/Views/todos/index.esw`:

```html
<%!
var conn: Connection
var todos: [Todo]
var flash: Flash
%>
<h1>My Todos</h1>

<% if let msg = flash.info { %>
    <p role="alert"><%= msg %></p>
<% } %>

<p><a href="/todos/new" role="button">New Todo</a></p>

<% if todos.isEmpty { %>
    <p>No todos yet. Create your first one!</p>
<% } else { %>
    <table>
        <thead>
            <tr>
                <th>Done</th>
                <th>Title</th>
                <th>Created</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody>
        <% for todo in todos { %>
            <tr>
                <td><%= todo.completed ? "done" : "pending" %></td>
                <td><a href="/todos/<%= todo.id %>"><%= todo.title %></a></td>
                <td><%= todo.createdAt %></td>
                <td>
                    <a href="/todos/<%= todo.id %>/edit">Edit</a>
                </td>
            </tr>
        <% } %>
        </tbody>
    </table>
<% } %>
```

### Show Page

Create `Sources/TodoApp/Views/todos/show.esw`:

```html
<%!
var conn: Connection
var todo: Todo
%>
<h1><%= todo.title %></h1>

<p><small>Created: <%= todo.createdAt %></small></p>
<p>Status: <strong><%= todo.completed ? "Completed" : "Pending" %></strong></p>

<% if let body = todo.body { %>
    <p><%= body %></p>
<% } %>

<p>
    <a href="/todos">Back</a>
    <a href="/todos/<%= todo.id %>/edit">Edit</a>
</p>

<form method="post" action="/todos/<%= todo.id %>">
    <input type="hidden" name="_method" value="DELETE">
    <button type="submit" class="secondary outline">Delete</button>
</form>
```

### New / Edit Forms

Create `Sources/TodoApp/Views/todos/new.esw`:

```html
<%!
var conn: Connection
var csrfToken: String
%>
<h1>New Todo</h1>

<form method="post" action="/todos">
    <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">

    <label>
        Title
        <input type="text" name="title" required autofocus>
    </label>

    <label>
        Notes
        <textarea name="body"></textarea>
    </label>

    <button type="submit">Create Todo</button>
</form>

<p><a href="/todos">Cancel</a></p>
```

Create `Sources/TodoApp/Views/todos/edit.esw`:

```html
<%!
var conn: Connection
var todo: Todo
var csrfToken: String
%>
<h1>Edit Todo</h1>

<form method="post" action="/todos/<%= todo.id %>">
    <input type="hidden" name="_method" value="PUT">
    <input type="hidden" name="_csrf_token" value="<%= csrfToken %>">

    <label>
        Title
        <input type="text" name="title" value="<%= todo.title %>" required>
    </label>

    <label>
        Notes
        <textarea name="body"><%= todo.body ?? "" %></textarea>
    </label>

    <label>
        <input type="checkbox" name="completed" <%= todo.completed ? "checked" : "" %>>
        Completed
    </label>

    <button type="submit">Update Todo</button>
</form>

<p><a href="/todos/<%= todo.id %>">Cancel</a></p>
```

### HTML Routes

Create `Sources/TodoApp/Routes/TodoPages.swift`:

```swift
import Peregrine

@RouteBuilder
func todoPageRoutes() -> [Route] {

    GET("/todos") { conn in
        let todos = try await conn.repo().all(Todo.self)
        return try conn.render("todos/index", ["todos": todos])
    }

    GET("/todos/new") { conn in
        return try conn.render("todos/new", [:])
    }

    GET("/todos/:id") { conn in
        guard let id = conn.params["id"].flatMap(UUID.init) else {
            throw NexusHTTPError(.badRequest, message: "Invalid ID")
        }
        guard let todo = try await conn.repo().get(Todo.self, id: id) else {
            throw NexusHTTPError(.notFound, message: "Todo not found")
        }
        return try conn.render("todos/show", ["todo": todo])
    }

    POST("/todos") { conn in
        let input = try conn.decode(as: CreateTodoInput.self)

        var changeset = Changeset(data: input, action: .create)
        await changeset.validate(using: [
            .required("title") { $0.title },
            .length("title", { $0.title }, min: 1, max: 200),
        ])

        let validated = try changeset.requireValid()

        var todo = Todo()
        todo.title = validated.title
        todo.body = validated.body
        todo.completed = false
        todo.position = 0

        let created = try await conn.repo().insert(todo)
        return conn
            .putFlash(.info, "Todo created!")
            .redirect(to: "/todos/\(created.id)")
    }

    GET("/todos/:id/edit") { conn in
        guard let id = conn.params["id"].flatMap(UUID.init) else {
            throw NexusHTTPError(.badRequest, message: "Invalid ID")
        }
        guard let todo = try await conn.repo().get(Todo.self, id: id) else {
            throw NexusHTTPError(.notFound, message: "Todo not found")
        }
        return try conn.render("todos/edit", ["todo": todo])
    }

    PUT("/todos/:id") { conn in
        guard let id = conn.params["id"].flatMap(UUID.init) else {
            throw NexusHTTPError(.badRequest, message: "Invalid ID")
        }
        guard var todo = try await conn.repo().get(Todo.self, id: id) else {
            throw NexusHTTPError(.notFound, message: "Todo not found")
        }

        let input = try conn.decode(as: CreateTodoInput.self)
        todo.title = input.title
        todo.body = input.body
        todo.completed = conn.bodyParams["completed"] != nil
        todo.updatedAt = Date()

        try await conn.repo().insert(todo)
        return conn
            .putFlash(.info, "Todo updated!")
            .redirect(to: "/todos/\(id)")
    }

    DELETE("/todos/:id") { conn in
        guard let id = conn.params["id"].flatMap(UUID.init) else {
            throw NexusHTTPError(.badRequest, message: "Invalid ID")
        }
        try await conn.repo().delete(Todo.self, id: id)
        return conn
            .putFlash(.info, "Todo deleted.")
            .redirect(to: "/todos")
    }
}
```

Key concepts:

- **`conn.render("todos/index", [...])`** renders an ESW template with the given assigns. `conn`, `flash`, and `csrfToken` are injected automatically.
- **`conn.putFlash(.info, "...")`** queues a one-time message shown on the next request.
- **`conn.redirect(to:)`** sends a 303 redirect.
- **`conn.bodyParams["completed"]`** reads raw form data for checkbox fields (present = checked).

---

## 7. Add Sessions, Flash, and CSRF

Update `App.swift` to wire in sessions, flash messages, CSRF protection, and both route groups:

```swift
import Peregrine

@main
struct TodoApp: PeregrineApp {
    let database = Database.postgres(database: "todo_app")

    var sessionStore: SessionStore? {
        MemorySessionStore()
    }

    var plugs: [Plug] {
        [
            requestId(),
            requestLogger(),
            sessionPlug(store: MemorySessionStore()),
            flashPlug(),
            peregrine_csrfProtection(),
        ]
    }

    @RouteBuilder var routes: [Route] {
        // HTML pages
        GET("/") { conn in
            conn.redirect(to: "/todos")
        }

        todoPageRoutes()

        // JSON API
        todoAPIRoutes()
    }
}
```

The **plug pipeline** runs on every request, left to right:

1. `requestId()` — assigns a unique request ID
2. `requestLogger()` — logs method, path, and duration
3. `sessionPlug()` — loads/persists session data from cookies
4. `flashPlug()` — reads flash messages from session, clears after display
5. `peregrine_csrfProtection()` — validates `_csrf_token` on form POSTs, injects `csrfToken` into assigns

---

## 8. Extract a Context

As your app grows, route handlers accumulate database logic. Peregrine borrows the **Context pattern** from Phoenix to keep handlers thin.

Create `Sources/TodoApp/Contexts/Todos.swift`:

```swift
import Peregrine

struct Todos {
    let conn: Connection

    func list() async throws -> [Todo] {
        try await conn.repo().all(Todo.self)
    }

    func get(id: UUID) async throws -> Todo {
        guard let todo = try await conn.repo().get(Todo.self, id: id) else {
            throw NexusHTTPError(.notFound, message: "Todo not found")
        }
        return todo
    }

    func create(_ input: CreateTodoInput) async throws -> Todo {
        var changeset = Changeset(data: input, action: .create)
        await changeset.validate(using: Self.rules)
        let validated = try changeset.requireValid()

        var todo = Todo()
        todo.title = validated.title
        todo.body = validated.body
        todo.completed = false
        todo.position = 0
        return try await conn.repo().insert(todo)
    }

    func update(_ todo: Todo, with input: CreateTodoInput, completed: Bool) async throws -> Todo {
        var updated = todo
        updated.title = input.title
        updated.body = input.body
        updated.completed = completed
        updated.updatedAt = Date()
        return try await conn.repo().insert(updated)
    }

    func delete(id: UUID) async throws {
        try await conn.repo().delete(Todo.self, id: id)
    }

    // MARK: - Validation Rules

    static let rules: [ValidatorRule<CreateTodoInput>] = [
        .required("title") { $0.title },
        .length("title", { $0.title }, min: 1, max: 200),
    ]
}
```

Now your route handlers become much simpler:

```swift
POST("/todos") { conn in
    let input = try conn.decode(as: CreateTodoInput.self)
    let todo = try await Todos(conn: conn).create(input)
    return conn
        .putFlash(.info, "Todo created!")
        .redirect(to: "/todos/\(todo.id)")
}
```

---

## 9. Add Authentication

Let's protect the todo list behind a login. First, generate the auth scaffold:

```bash
peregrine gen.auth
```

This creates:

- `Sources/TodoApp/Models/User.swift` — User model with `hashedPassword`
- `Sources/TodoApp/Models/UserToken.swift` — Session tokens
- `Sources/TodoApp/Routes/AuthRoutes.swift` — Login, register, logout routes
- `Sources/TodoApp/Views/auth/login.esw` — Login form
- `Sources/TodoApp/Views/auth/register.esw` — Registration form
- `Migrations/2_create_users.sql` — Users table
- `Migrations/3_create_user_tokens.sql` — Token table

Run the migrations:

```bash
peregrine migrate up
```

### Protect Routes

Update `App.swift` to add authentication plugs:

```swift
import Peregrine

@main
struct TodoApp: PeregrineApp {
    let database = Database.postgres(database: "todo_app")

    var sessionStore: SessionStore? {
        MemorySessionStore()
    }

    var plugs: [Plug] {
        [
            requestId(),
            requestLogger(),
            sessionPlug(store: MemorySessionStore()),
            flashPlug(),
            peregrine_csrfProtection(),
        ]
    }

    @RouteBuilder var routes: [Route] {
        // Public routes
        GET("/") { conn in
            conn.redirect(to: "/todos")
        }

        authRoutes()

        // Protected routes — require login
        scope("/todos", plugs: [
            fetchSessionUser { userID, conn in
                guard let uuid = UUID(uuidString: userID) else { return nil }
                return try await conn.repo()
                    .query(User.self)
                    .filter(\.id == uuid)
                    .first()
            },
            requireAuth(),
        ]) {
            todoPageRoutes()
        }

        // API routes — require bearer token
        scope("/api", plugs: [
            fetchBearerUser { token, conn in
                let hashed = Auth.sha256Hex(token)
                guard let tokenRow = try await conn.repo()
                    .query(UserToken.self)
                    .filter(\.token == hashed)
                    .filter(\.context == "api")
                    .first()
                else { return nil }

                if let exp = tokenRow.expiresAt, exp < Date() { return nil }

                return try await conn.repo()
                    .query(User.self)
                    .filter(\.id == tokenRow.userId)
                    .first()
            },
            requireApiAuth(),
        ]) {
            todoAPIRoutes()
        }
    }
}
```

Key concepts:

- **`scope("/path", plugs: [...]) { ... }`** applies middleware to a group of routes.
- **`fetchSessionUser`** loads the user from the database using the session token. If it fails, the user continues as a guest.
- **`requireAuth()`** halts with a redirect to `/auth/login` if no user is loaded.
- **`fetchBearerUser`** validates the `Authorization: Bearer <token>` header for API routes.
- **`requireApiAuth()`** returns 401 if no bearer user is authenticated.

### Scope Todos by User

To make each user see only their own todos, add a `user_id` column:

```bash
peregrine gen migration add_user_id_to_todos
```

Edit the generated migration:

```sql
-- migrate:up
ALTER TABLE "todos" ADD COLUMN "user_id" UUID NOT NULL REFERENCES "users"("id");
CREATE INDEX "idx_todos_user_id" ON "todos"("user_id");

-- migrate:down
DROP INDEX "idx_todos_user_id";
ALTER TABLE "todos" DROP COLUMN "user_id";
```

Update the model:

```swift
@Schema("todos")
struct Todo {
    @ID var id: UUID
    @ForeignKey var userId: UUID    // <-- new
    @Column var title: String
    @Column var body: String?
    @Column var completed: Bool
    @Column var position: Int
    @Timestamp var createdAt: Date
    @Timestamp var updatedAt: Date
}
```

Update the context to scope queries:

```swift
struct Todos {
    let conn: Connection

    private var userId: UUID {
        let user = conn.currentUser(User.self)!
        return user.id
    }

    func list() async throws -> [Todo] {
        try await conn.repo()
            .query(Todo.self)
            .where(\.userId == userId)
            .all()
    }

    func create(_ input: CreateTodoInput) async throws -> Todo {
        var changeset = Changeset(data: input, action: .create)
        await changeset.validate(using: Self.rules)
        let validated = try changeset.requireValid()

        var todo = Todo()
        todo.userId = userId  // <-- scope to current user
        todo.title = validated.title
        todo.body = validated.body
        todo.completed = false
        todo.position = 0
        return try await conn.repo().insert(todo)
    }

    // ... get/update/delete also filter by userId
}
```

---

## 10. Run It

```bash
peregrine migrate up
swift build && .build/debug/TodoApp
```

Open `http://localhost:8080` in your browser. You'll be redirected to the login page. Register an account, then start creating todos.

---

## What You've Learned

| Concept | Where |
|---------|-------|
| App bootstrap | `@main struct TodoApp: PeregrineApp` |
| Routing DSL | `@RouteBuilder`, `GET`, `POST`, `scope` |
| Database models | `@Schema`, `@Column`, `@ID`, `@ForeignKey` |
| Queries | `conn.repo().all()`, `.get()`, `.insert()`, `.delete()` |
| JSON APIs | `conn.json(value:)`, `conn.decode(as:)` |
| Templates | ESW with `<%= %>`, `<%- %>`, `<% for ... { %>` |
| Validation | `Changeset<T>`, `ValidatorRule`, `.required()`, `.length()` |
| Sessions | `sessionPlug()`, `putSessionValue()`, `sessionValue()` |
| Flash messages | `putFlash(.info, "...")`, read via `flash.info` in templates |
| CSRF protection | `peregrine_csrfProtection()`, `csrfToken` in forms |
| Auth | `Auth.hashPassword()`, `loginUser()`, `requireAuth()` |
| Scoped routes | `scope("/path", plugs: [...]) { ... }` |
| Contexts | Phoenix-style `Todos` struct encapsulating DB logic |

## Next Steps

- Add drag-and-drop reordering with the `position` field
- Add due dates with the `.number()` validator for date ranges
- Add categories using `peregrine gen resource Category name:string`
- Deploy with `PEREGRINE_ENV=prod` and a Postgres-backed session store
- Add real-time updates with Peregrine Channels and PubSub

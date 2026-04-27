# Real-Time Polymarket Dashboard using Spring Boot, GraphQL, and React

**Objective**

> Build a full-stack real-time application that fetches prediction market data from Polymarket and displays selected markets with live price and volume updates using GraphQL Queries, Mutations, and Subscriptions.
>
>The users can browse Polymarket prediction markets, select a specific market, and choose one or more outcomes (bets). Once selected, the web application must automatically notify the user in real time with live price and volume updates for the chosen market using GraphQL Subscriptions over WebSocket.

**Requirements**

**Backend (Spring Boot + GraphQL)**

- Create a `Spring Boot` application that communicates with the `Polymarket Gamma API` (`https://gamma-api.polymarket.com`).
- Implement `GraphQL` support with Queries, Mutations, and Subscriptions.
- Use `WebSocket` (graphql-ws protocol) to enable **real-time** updates.
- Poll the Polymarket API periodically in the background and push updates to subscribed clients via GraphQL Subscriptions.
- Students must implement all Queries, Mutations, and Subscriptions themselves.

**Code:**

**1. Maven Dependencies (pom.xml)**

Add the following dependencies in your `pom.xml`:

```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-graphql</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-webflux</artifactId>
    </dependency>
    <dependency>
        <groupId>org.projectlombok</groupId>
        <artifactId>lombok</artifactId>
        <optional>true</optional>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-validation</artifactId>
    </dependency>
</dependencies>
```

**2. GraphQL Schema (src/main/resources/graphql/schema.graphqls)**

```graphql
type Query {
  markets(limit: Int = 20, active: Boolean = true): [Market!]!
  market(id: ID!): Market
  events: [Event!]
}

type Mutation {
  selectMarket(id: ID!): SelectedMarket!
  refreshMarket(id: ID!): Market
}

type Subscription {
  marketUpdated(marketId: ID!): MarketUpdate!
}

type Market {
  id: ID!
  slug: String!
  question: String!
  description: String
  outcomes: [Outcome!]!
  volume: Float
  liquidity: Float
  endDate: String
  active: Boolean
  category: String
}

type Outcome {
  tokenId: String!
  name: String!
  price: Float!
  volume: Float
}

type MarketUpdate {
  marketId: ID!
  outcomes: [Outcome!]!
  volume: Float
  liquidity: Float
  timestamp: String!
}

type Event {
  id: ID!
  title: String!
  markets: [Market!]
}

type SelectedMarket {
  marketId: ID!
  selectedAt: String!
  message: String
}
```

**Frontend (React)**

- Create a React application using `Apollo Client`.
- Configure Apollo Client to support <mark>both HTTP queries/mutations and WebSocket subscriptions (graphql-ws)</mark>.
- Build a `user interface` that allows:
  - Browsing and searching markets
  - Selecting a specific market
  - Viewing real-time price and volume updates for the selected market’s outcomes
- Use GraphQL Queries to load initial data, Mutations for user actions (select/refresh), and Subscriptions for live updates.

**Lab Tasks**

1. Implement the complete GraphQL backend layer:
   
   - Create necessary DTOs / Records for Market, Outcome, MarketUpdate, etc.
   - Build a service to fetch data from Polymarket Gamma API using WebClient or RestTemplate.
   - Implement all Query resolvers.
   - Implement all Mutation resolvers.
   - Implement the Subscription resolver using reactive `Sinks` or equivalent for broadcasting updates.
   - Configure a scheduled task to poll Polymarket API and publish updates via Subscription.

2. Set up GraphQL WebSocket support for subscriptions.

3. In the React frontend:
   
   - Set up Apollo Client with split link (HTTP + WebSocket).
   - Implement queries to fetch markets and single market details.
   - Implement mutations for selecting and refreshing a market.
   - Implement subscription to receive live `marketUpdated` data.
   - Create a responsive UI with market list and a detailed real-time dashboard for the selected market (showing outcomes with live price changes).

4. Handle subscription connection, reconnection, and error cases gracefully.

**Important Notes**

- Do not hardcode Polymarket data. Always fetch from the live API.
- Students are responsible for designing the resolvers, services, and components.
- Focus on proper separation of concerns between Query, Mutation, and Subscription.
- The subscription should push updates whenever new data is polled from Polymarket.

**Submission**

- Full Spring Boot backend project
- React frontend project
- Screenshots of:
  - GraphiQL / Altair showing queries, mutations, and active subscription
  - React dashboard with live updating prices

**Estimated Time**: 18–24 hours (3 dyas of work)

Good luck! Focus on understanding how Queries, Mutations, and Subscriptions work together in a real-time GraphQL application.



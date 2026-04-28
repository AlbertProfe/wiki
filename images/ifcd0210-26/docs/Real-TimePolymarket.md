---
title: "Lab Polymarket"
categories: [labs]
toc: true
number-sections: false
format:
  html
---

# Real-Time Polymarket Dashboard using Spring Boot, GraphQL, and React

## Objective

> Build a full-stack real-time application that fetches prediction market data from Polymarket and displays selected markets with live price and volume updates using GraphQL Queries, Mutations, and Subscriptions.
>
>The users can browse Polymarket prediction markets, select a specific market, and choose one or more outcomes (bets). Once selected, the web application must automatically notify the user in real time with live price and volume updates for the chosen market using GraphQL Subscriptions over WebSocket.


## Features

Let's start with 3 basic features, these three features form a solid and progressive scope for the project:

- **Feature 0** handles security and user management.
- **Feature 1** focuses on discovery and real-time data display.
- **Feature 2** adds user interaction and personalization.

### Feature 0: Authentication System (Login / Register)

**Description**:

>Implement a user authentication system that allows new users to create an account and existing users to log in. The system must securely handle user registration and login using email and password. Once authenticated, users gain access to personalized features such as saving favorites and making predictions. JWT-based authentication is recommended for securing the backend APIs.
> If you do not want to use JWT you can proopose and alternative.

**Main Requirements**:

- User registration with email, password, and username.
- User login with email and password.
- Password hashing and secure token generation.
- Protected routes for authenticated users only.
- Basic profile information (optional).

## Feature 1: Dashboard – Most Relevant Markets Summary

**Description**:

> Develop a clean and informative dashboard that displays a summary of the **10 most relevant active markets** from Polymarket. The dashboard serves as the main landing page after login, giving users a quick overview of trending or high-volume prediction markets.

**Main Requirements**:

- Show the top 10 markets sorted by volume, liquidity, or activity (students can choose the best criteria).
- For each market, display: question/title, category, current volume, liquidity, end date, and the top 2–3 outcomes with their current prices.
- Responsive and visually appealing card-based layout.
- Clicking on any market card redirects the user to the detailed market view.
- Data must be fetched from Polymarket Gamma API and refreshed periodically.

### Feature 2: Favorites & Make a Prediction

**Description**:

> Allow authenticated users to add interesting markets to their personal **Favorites** list and make a prediction (simulate placing a bet) on a selected outcome within a chosen market.

**Main Requirements**

- Users can add or remove a market from their Favorites list (using GraphQL Mutations).
- A dedicated “My Favorites” section where saved markets are displayed with live price updates.
- In the market detail view, users can select one outcome and “make a prediction” by specifying an amount (simulation only – no real trading).
- Store the user’s favorite markets and prediction history in the backend database.
- After making a prediction, show a confirmation message and update the user interface in real time where applicable.
- The selected market must continue receiving live price updates via GraphQL Subscription.

## Requirements

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

## Lab Tasks

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

**Estimated Time**: 18–24 hours (3 days of work (focused)/ 4 weeks - 4 sprints (shared time))

Good luck! Focus on understanding how Queries, Mutations, and Subscriptions work together in a real-time GraphQL application.



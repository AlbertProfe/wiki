# People & Cars example algorithm

## With static

Here’s a simple classic Java example using `ArrayList`:

```java
import java.util.ArrayList;

public class Main {

    // Simple Person class
    static class Person {
        String name;
        int age;

        Person(String name, int age) {
            this.name = name;
            this.age = age;
        }

        @Override
        public String toString() {
            return "Person{name='" + name + "', age=" + age + "}";
        }
    }

    public static void main(String[] args) {
        // Create the ArrayList
        ArrayList<Person> people = new ArrayList<>();

        // Add 10 Person objects
        for (int i = 1; i <= 10; i++) {
            people.add(new Person("Person" + i, 20 + i));
        }

        // Print the list
        System.out.println(people);
    }
}
```

### Output example:
```
[Person{name='Person1', age=21}, Person{name='Person2', age=22}, ... , Person{name='Person10', age=30}]
```

You can change the `name` and `age` values inside the loop as needed.



In the example, `Person` is declared as a **static nested class** inside `Main`.

## Why `static`?

```java
static class Person {
    ...
}
```

- A **non-static** inner class is tied to an instance of the outer class (`Main`).  
  You would need an object of `Main` just to create a `Person`.

- A **static** nested class does **not** need an instance of the outer class.  
  You can create it directly with `new Person(...)`, which is what we have at simple example.

### Alternative (more common in real projects)

Most people prefer putting the `Person` class in its **own file**:

```java
// Person.java
public class Person {
    String name;
    int age;

    public Person(String name, int age) {
        this.name = name;
        this.age = age;
    }

    @Override
    public String toString() {
        return "Person{name='" + name + "', age=" + age + "}";
    }
}
```

```java
// Main.java
import java.util.ArrayList;

public class Main {
    public static void main(String[] args) {
        ArrayList<Person> people = new ArrayList<>();

        for (int i = 1; i <= 10; i++) {
            people.add(new Person("Person" + i, 20 + i));
        }

        System.out.println(people);
    }
}
```

This way we don’t need `static` at all.
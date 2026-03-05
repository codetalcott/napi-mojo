// Classes: Counter with methods, getters, static methods, and Dog inheritance
const m = require('../build/index.node');

const counter = new m.Counter(10);
console.log(counter.value);              // 10
counter.increment();
console.log(counter.value);              // 11
counter.reset();
console.log(counter.value);              // 10 (reset to initial)
console.log(m.Counter.isCounter(counter)); // true
console.log(m.Counter.isCounter({}));    // false

const c2 = m.Counter.fromValue(42);
console.log(c2.value);                  // 42

// Inheritance: Dog extends Animal
const dog = new m.Dog('Rex', 'Labrador');
console.log(dog.name);                  // "Rex"
console.log(dog.breed);                 // "Labrador"
console.log(dog.speak());               // "Rex says hello"
console.log(m.Animal.isAnimal(dog));     // true

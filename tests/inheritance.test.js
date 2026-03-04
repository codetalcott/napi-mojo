const addon = require('../build/index.node');

describe('Class Inheritance (Animal → Dog)', () => {
  describe('Animal class', () => {
    test('new Animal("Cat") returns an object', () => {
      const a = new addon.Animal('Cat');
      expect(typeof a).toBe('object');
    });

    test('Animal name getter returns correct name', () => {
      const a = new addon.Animal('Cat');
      expect(a.name).toBe('Cat');
    });

    test('Animal speak() returns "<name> says hello"', () => {
      const a = new addon.Animal('Cat');
      expect(a.speak()).toBe('Cat says hello');
    });

    test('Animal.isAnimal(animal) returns true', () => {
      const a = new addon.Animal('Cat');
      expect(addon.Animal.isAnimal(a)).toBe(true);
    });

    test('Animal.isAnimal({}) returns false', () => {
      expect(addon.Animal.isAnimal({})).toBe(false);
    });

    test('Animal.isAnimal(42) returns false for primitives', () => {
      expect(addon.Animal.isAnimal(42)).toBe(false);
    });
  });

  describe('Dog class', () => {
    test('new Dog("Rex", "Labrador") returns an object', () => {
      const d = new addon.Dog('Rex', 'Labrador');
      expect(typeof d).toBe('object');
    });

    test('Dog breed getter returns correct breed', () => {
      const d = new addon.Dog('Rex', 'Labrador');
      expect(d.breed).toBe('Labrador');
    });

    test('Dog inherits name getter from Animal', () => {
      const d = new addon.Dog('Rex', 'Labrador');
      expect(d.name).toBe('Rex');
    });

    test('Dog inherits speak() from Animal', () => {
      const d = new addon.Dog('Rex', 'Labrador');
      expect(d.speak()).toBe('Rex says hello');
    });

    test('dog instanceof Dog is true', () => {
      const d = new addon.Dog('Rex', 'Labrador');
      expect(d instanceof addon.Dog).toBe(true);
    });

    test('dog instanceof Animal is true (prototype chain)', () => {
      const d = new addon.Dog('Rex', 'Labrador');
      expect(d instanceof addon.Animal).toBe(true);
    });

    test('Animal.isAnimal(dog) returns true', () => {
      const d = new addon.Dog('Rex', 'Labrador');
      expect(addon.Animal.isAnimal(d)).toBe(true);
    });

    test('animal instanceof Dog is false', () => {
      const a = new addon.Animal('Cat');
      expect(a instanceof addon.Dog).toBe(false);
    });
  });

  describe('Multiple instances', () => {
    test('multiple independent Dog instances', () => {
      const d1 = new addon.Dog('Rex', 'Labrador');
      const d2 = new addon.Dog('Buddy', 'Poodle');
      expect(d1.name).toBe('Rex');
      expect(d1.breed).toBe('Labrador');
      expect(d2.name).toBe('Buddy');
      expect(d2.breed).toBe('Poodle');
    });

    test('multiple Animals and Dogs coexist', () => {
      const a = new addon.Animal('Cat');
      const d = new addon.Dog('Rex', 'Labrador');
      expect(a.name).toBe('Cat');
      expect(d.name).toBe('Rex');
      expect(a instanceof addon.Animal).toBe(true);
      expect(d instanceof addon.Animal).toBe(true);
      expect(a instanceof addon.Dog).toBe(false);
      expect(d instanceof addon.Dog).toBe(true);
    });
  });
});

import Foundation


enum ReadWriteLockError: Error {
    case cantCreateRwLock(code: Int32)
    case cantAquireReadLock(code: Int32)
    case cantAquireWriteLock(code: Int32)
    case cantUnlock(code: Int32)
}

fileprivate class ReadWriteLock {
    private var sysLock = pthread_rwlock_t()
    
    init() throws {
        try ReadWriteLock.tryInteractWithLock(lockInteractor: {
            pthread_rwlock_init(&sysLock, nil)
        }, errorProducer: {
            ReadWriteLockError.cantCreateRwLock(code: $0)
        })
    }
    
    private static func tryInteractWithLock(lockInteractor: () -> Int32, errorProducer: (Int32) -> ReadWriteLockError) throws {
        let code = lockInteractor()
        guard code == 0 else {
            throw errorProducer(code)
        }
    }
    
    private func doInLockedState<T>(_ action: () -> T) throws -> T {
        let result = action()
        try unlock()
        
        return result
    }
    
    func withReadLock<T>(action: () -> T) throws -> T {
        try ReadWriteLock.tryInteractWithLock(lockInteractor: {
            pthread_rwlock_rdlock(&sysLock)
        }, errorProducer: {
            ReadWriteLockError.cantAquireReadLock(code: $0)
        })
        
        return try doInLockedState(action)
    }
    
    func withWriteLock<T>(action: () -> T) throws -> T {
        try ReadWriteLock.tryInteractWithLock(lockInteractor: {
            pthread_rwlock_wrlock(&sysLock)
        }, errorProducer: {
            ReadWriteLockError.cantAquireWriteLock(code: $0)
        })
        
        return try doInLockedState(action)
    }
    
    func unlock() throws {
        try ReadWriteLock.tryInteractWithLock(lockInteractor: {
            pthread_rwlock_unlock(&sysLock)
        }, errorProducer: {
            ReadWriteLockError.cantUnlock(code: $0)
        })
    }
    
    deinit {
        pthread_rwlock_destroy(&sysLock)
    }
}

public class ThreadSafeArray<T> {
    private var array: [T] = []
    private let readWriteLock: ReadWriteLock
    
    public init() {
        readWriteLock = try! ReadWriteLock()
    }

}


/**
 *** Мотивация к использованию ``try!`` внутри ThreadSafeArray
 
    Использование системного RWLock предполагает возможность возникновения ошибок (для этого в методах
 *    вызова (pthread`*`) возвращается код результата). Архитектурно, создавая обёртку для него в Swift можно поступить несколькими способами:
 *    1. Забить на ошибки (не надо так делать имхо)
 *    2. Кидать fatalError() на каждую ошибку
 *    3. Кидать свою ошибку (как решил сделать я)
 *
 * При использовании 3го варианта возникает проблема, что в Swift нельзя выкидывать Unchecked exceptions (и ловить их, как, например, <? extends RuntimeException> в Java). Поэтому, чтобы оставить для будущих реализаций чего-либо, использующего мою реализацию ReadWriteLock, возможность лоавить ошибки и делать с ними что-то осмысленное, я выбрал пункт 3. Однако, контракт RandomAccessCollection изначально не содерджит бросающих методов, поэтому пришлось привести мой вариант 3 к варианту 2 (как раз таки используя ``try!``)
 */
extension ThreadSafeArray: RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = T

    
    public var startIndex: Index { return try! readWriteLock.withReadLock(action: { array.startIndex }) }
    public var endIndex: Index { return try! readWriteLock.withReadLock(action: { array.endIndex }) }

    public subscript(index: Index) -> Element {
        get { 
            return try! readWriteLock.withReadLock(action: { array[index] })
        }
        
        set {
            return try! readWriteLock.withWriteLock(action: { array[index] = newValue })
        }
    }

    public func index(after i: Index) -> Index {
        return try! readWriteLock.withReadLock(action: { array.index(after: i) })
    }
    
    public func append(_ element: Element) {
        try! readWriteLock.withWriteLock(action: { array.append(element)})
    }
}

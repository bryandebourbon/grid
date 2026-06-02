import Foundation
import CloudKit

final class ReportService {
    private let publicDB: CKDatabase

    init(publicDB: CKDatabase = CKContainer.default().publicCloudDatabase) {
        self.publicDB = publicDB
    }

    func submit(_ report: Report, completion: @escaping (Result<Void, Error>) -> Void) {
        publicDB.save(report.toCKRecord()) { _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
}

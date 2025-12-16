import Foundation
import Contacts

struct ContactInfo: Identifiable, Codable {
    let id: String
    let name: String
    let email: String?
}

@MainActor
class ContactService: ObservableObject {
    private let store = CNContactStore()
    @Published var isAuthorized = false
    
    init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        isAuthorized = (status == .authorized)
    }
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            isAuthorized = granted
            return granted
        } catch {
            print("❌ [ContactService] Access request failed: \(error)")
            return false
        }
    }
    
    func searchContacts(query: String) async -> [ContactInfo] {
        print("🔍 [ContactService] Searching for '\(query)'...")
        
        guard isAuthorized else { 
            print("❌ [ContactService] Not authorized to search contacts. Status: \(CNContactStore.authorizationStatus(for: .contacts).rawValue)")
            return [] 
        }
        
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: query)
        
        do {
            var contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            
            // Fallback: If no contacts found, try manual filtering (predicate can be strict)
            if contacts.isEmpty {
                print("   ⚠️ No matches with predicate. Trying fallback search...")
                let allContainers = try store.containers(matching: nil)
                for container in allContainers {
                    let fetchPredicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
                    let containerContacts = try store.unifiedContacts(matching: fetchPredicate, keysToFetch: keys)
                    
                    let filtered = containerContacts.filter { contact in
                        let fullName = "\(contact.givenName) \(contact.familyName)"
                        return fullName.localizedCaseInsensitiveContains(query)
                    }
                    contacts.append(contentsOf: filtered)
                }
            }
            
            print("   Found \(contacts.count) matches for '\(query)'")
            
            return contacts.compactMap { contact in
                let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                let email = contact.emailAddresses.first?.value as String?
                
                // Only return contacts with emails for scheduling purposes
                if let email = email, !email.isEmpty {
                    print("   ✅ Match: \(name) (\(email))")
                    return ContactInfo(id: contact.identifier, name: name, email: email)
                } else {
                    print("   ⚠️ Skipped \(name) - No email found")
                }
                return nil
            }
        } catch {
            print("⚠️ [ContactService] Search error: \(error)")
            return []
        }
    }
}

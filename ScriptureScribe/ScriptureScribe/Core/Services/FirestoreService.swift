//
//  FirestoreService.swift
//  ScriptureScribe
//
//  Single service for all Firestore reads and writes.
//
//  Firestore collections:
//    users/{uid}                          ← AppUser
//    users/{uid}/bookmarks/{id}           ← Bookmark
//    users/{uid}/notes/{id}               ← UserNote
//    posts/{postId}                       ← Post
//    posts/{postId}/comments/{commentId}  ← Comment
//

import FirebaseFirestore
import Foundation

final class FirestoreService {

    private let db = Firestore.firestore()

    // MARK: - Users

    func createUser(_ user: AppUser) async throws {
        var data: [String: Any] = [
            "displayName": user.displayName,
            "email":       user.email,
            "createdAt":   Timestamp(date: user.createdAt)
        ]
        if let photoURL = user.photoURL { data["photoURL"] = photoURL }
        try await db.collection("users").document(user.id).setData(data)
    }

    func updateUserPhoto(userId: String, photoURL: String) async throws {
        try await db.collection("users").document(userId).updateData(["photoURL": photoURL])
    }

    func fetchUser(userId: String) async throws -> AppUser? {
        let doc = try await db.collection("users").document(userId).getDocument()
        return decodeUser(doc)
    }

    private func decodeUser(_ doc: DocumentSnapshot) -> AppUser? {
        guard doc.exists, let data = doc.data() else { return nil }
        return AppUser(
            id:          doc.documentID,
            displayName: data["displayName"] as? String ?? "",
            email:       data["email"] as? String ?? "",
            createdAt:   (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            photoURL:    data["photoURL"] as? String
        )
    }

    // MARK: - Posts

    /// Fetches the most recent posts for the feed.
    func fetchFeed(limit: Int = 40, after lastDoc: DocumentSnapshot? = nil) async throws -> ([Post], DocumentSnapshot?) {
        var query: Query = db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        if let last = lastDoc {
            query = query.start(afterDocument: last)
        }
        let snapshot = try await query.getDocuments()
        let posts = snapshot.documents.compactMap { decodePost($0) }
        return (posts, snapshot.documents.last)
    }

    /// Attaches a real-time listener to the feed. Call `remove()` on the returned handle to stop.
    func listenToFeed(onChange: @escaping ([Post]) -> Void) -> ListenerRegistration {
        db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { snapshot, error in
                guard error == nil, let snapshot else { onChange([]); return }
                let posts = snapshot.documents.compactMap { self.decodePost($0) }
                onChange(posts)
            }
    }

    func createPost(_ post: Post) async throws {
        var data: [String: Any] = [
            "userId":       post.userId,
            "displayName":  post.displayName,
            "text":         post.text,
            "verseRef":     post.verseRef,
            "verseText":    post.verseText,
            "createdAt":    Timestamp(date: post.createdAt),
            "commentCount": post.commentCount,
            "likeCount":    post.likeCount
        ]
        if let photoURL = post.photoURL { data["photoURL"] = photoURL }
        try await db.collection("posts").document(post.id).setData(data)
    }

    func deletePost(postId: String) async throws {
        try await db.collection("posts").document(postId).delete()
    }

    func updatePost(postId: String, text: String) async throws {
        try await db.collection("posts").document(postId).updateData(["text": text])
    }

    /// Admin: update multiple fields on a post (text, verse, display name).
    func updatePostFields(postId: String, fields: [String: Any]) async throws {
        try await db.collection("posts").document(postId).updateData(fields)
    }

    /// Admin: update a user's display name in their profile document.
    func updateUserDisplayName(userId: String, displayName: String) async throws {
        try await db.collection("users").document(userId).updateData(["displayName": displayName])
    }

    private func decodePost(_ doc: DocumentSnapshot) -> Post? {
        guard let data = doc.data() else { return nil }
        return Post(
            id:           doc.documentID,
            userId:       data["userId"]       as? String ?? "",
            displayName:  data["displayName"]  as? String ?? "",
            photoURL:     data["photoURL"]     as? String,
            text:         data["text"]         as? String ?? "",
            verseRef:     data["verseRef"]     as? String ?? "",
            verseText:    data["verseText"]    as? String ?? "",
            createdAt:    (data["createdAt"]   as? Timestamp)?.dateValue() ?? Date(),
            commentCount: data["commentCount"] as? Int ?? 0,
            likeCount:    data["likeCount"]    as? Int ?? 0
        )
    }

    // MARK: - Post Likes

    /// Adds or removes the current user's ♥ like on a reflection post.
    func togglePostLike(postId: String, userId: String, isLiked: Bool) async throws {
        let likeRef = db.collection("posts").document(postId)
            .collection("postLikes").document(userId)
        let postRef = db.collection("posts").document(postId)

        if isLiked {
            try await likeRef.delete()
            try await postRef.updateData(["likeCount": FieldValue.increment(Int64(-1))])
        } else {
            try await likeRef.setData(["userId": userId, "likedAt": Timestamp(date: Date())])
            try await postRef.updateData(["likeCount": FieldValue.increment(Int64(1))])
        }
    }

    /// Returns the post IDs that this user has already liked.
    func fetchLikedPostIds(userId: String) async throws -> [String] {
        let snapshot = try await db.collectionGroup("postLikes")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        return snapshot.documents
            .map { $0.reference.parent.parent?.documentID ?? "" }
            .filter { !$0.isEmpty }
    }

    // MARK: - Comments

    func fetchComments(postId: String) async throws -> [Comment] {
        let snapshot = try await db.collection("posts").document(postId)
            .collection("comments")
            .order(by: "createdAt")
            .getDocuments()
        return snapshot.documents.compactMap { decodeComment($0, postId: postId) }
    }

    func addComment(_ comment: Comment) async throws {
        let ref = db.collection("posts").document(comment.postId)
            .collection("comments").document(comment.id)
        var data: [String: Any] = [
            "userId":      comment.userId,
            "displayName": comment.displayName,
            "text":        comment.text,
            "likeCount":   0,
            "createdAt":   Timestamp(date: comment.createdAt)
        ]
        if let photoURL = comment.photoURL { data["photoURL"] = photoURL }
        if let parentId = comment.parentCommentId { data["parentCommentId"] = parentId }
        try await ref.setData(data)
        // Increment the comment count on the post document
        try await db.collection("posts").document(comment.postId).updateData([
            "commentCount": FieldValue.increment(Int64(1))
        ])
    }

    private func decodeComment(_ doc: DocumentSnapshot, postId: String) -> Comment? {
        guard let data = doc.data() else { return nil }
        return Comment(
            id:              doc.documentID,
            postId:          postId,
            userId:          data["userId"]          as? String ?? "",
            displayName:     data["displayName"]     as? String ?? "",
            photoURL:        data["photoURL"]        as? String,
            text:            data["text"]            as? String ?? "",
            likeCount:       data["likeCount"]       as? Int ?? 0,
            parentCommentId: data["parentCommentId"] as? String,
            createdAt:       (data["createdAt"]      as? Timestamp)?.dateValue() ?? Date()
        )
    }

    // MARK: - Comment Actions (generic)

    /// Updates the text of a comment under any parent collection.
    func updateComment(parentCollection: String, parentId: String, commentId: String, text: String) async throws {
        try await db.collection(parentCollection).document(parentId)
            .collection("comments").document(commentId)
            .updateData(["text": text])
    }

    /// Deletes a comment and decrements the parent's commentCount.
    func deleteComment(parentCollection: String, parentId: String, commentId: String) async throws {
        try await db.collection(parentCollection).document(parentId)
            .collection("comments").document(commentId).delete()
        try await db.collection(parentCollection).document(parentId)
            .updateData(["commentCount": FieldValue.increment(Int64(-1))])
    }

    /// Toggles a like on a comment. Uses subcollection: comments/{id}/commentLikes/{userId}.
    func toggleCommentLike(parentCollection: String, parentId: String, commentId: String, userId: String, isLiked: Bool) async throws {
        let commentRef = db.collection(parentCollection).document(parentId)
            .collection("comments").document(commentId)
        let likeRef = commentRef.collection("commentLikes").document(userId)

        if isLiked {
            try await likeRef.delete()
            try await commentRef.updateData(["likeCount": FieldValue.increment(Int64(-1))])
        } else {
            try await likeRef.setData(["userId": userId, "likedAt": Timestamp(date: Date())])
            try await commentRef.updateData(["likeCount": FieldValue.increment(Int64(1))])
        }
    }

    /// Returns the comment IDs that this user has liked across all comment sections.
    func fetchLikedCommentIds(userId: String) async throws -> [String] {
        let snapshot = try await db.collectionGroup("commentLikes")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        return snapshot.documents
            .map { $0.reference.parent.parent?.documentID ?? "" }
            .filter { !$0.isEmpty }
    }

    // MARK: - Bookmarks

    func saveBookmark(_ bookmark: Bookmark, userId: String) async throws {
        let ref = db.collection("users").document(userId)
            .collection("bookmarks").document(bookmark.id)
        var data: [String: Any] = [
            "bibleId":          bookmark.bibleId,
            "bookId":           bookmark.bookId,
            "chapterId":        bookmark.chapterId,
            "chapterReference": bookmark.chapterReference,
            "verseId":          bookmark.verseId,
            "verseIdEnd":       bookmark.verseIdEnd,
            "verseText":        bookmark.verseText,
            "colorHex":         bookmark.colorHex,
            "emoji":            bookmark.emoji,
            "createdAt":        Timestamp(date: bookmark.createdAt)
        ]
        if !bookmark.groupIds.isEmpty { data["groupIds"] = bookmark.groupIds }
        try await ref.setData(data)
    }

    func deleteBookmark(id: String, userId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("bookmarks").document(id).delete()
    }

    func fetchBookmarks(userId: String) async throws -> [Bookmark] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("bookmarks")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { decodeBookmark($0) }
    }

    private func decodeBookmark(_ doc: DocumentSnapshot) -> Bookmark? {
        guard let data = doc.data() else { return nil }
        return Bookmark(
            id:               doc.documentID,
            bibleId:          data["bibleId"]          as? String ?? "",
            bookId:           data["bookId"]            as? String ?? "",
            chapterId:        data["chapterId"]         as? String ?? "",
            chapterReference: data["chapterReference"]  as? String ?? "",
            verseId:          data["verseId"]           as? String ?? "",
            verseIdEnd:       data["verseIdEnd"]        as? String ?? "",
            verseText:        data["verseText"]         as? String ?? "",
            colorHex:         data["colorHex"]          as? String ?? "F5C842",
            emoji:            data["emoji"]             as? String ?? "⭐",
            groupIds: {
                // Backward compat: try groupIds array first, then fall back to single groupId
                if let ids = data["groupIds"] as? [String], !ids.isEmpty { return ids }
                if let single = data["groupId"] as? String, !single.isEmpty { return [single] }
                return []
            }(),
            createdAt:        (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    // MARK: - Bookmark Groups

    func saveBookmarkGroup(_ group: BookmarkGroup, userId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("bookmarkGroups").document(group.id).setData([
                "name":      group.name,
                "colorHex":  group.colorHex,
                "emoji":     group.emoji,
                "createdAt": Timestamp(date: group.createdAt)
            ])
    }

    func deleteBookmarkGroup(id: String, userId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("bookmarkGroups").document(id).delete()
    }

    func fetchBookmarkGroups(userId: String) async throws -> [BookmarkGroup] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("bookmarkGroups")
            .order(by: "createdAt")
            .getDocuments()
        return snapshot.documents.compactMap { decodeBookmarkGroup($0) }
    }

    private func decodeBookmarkGroup(_ doc: DocumentSnapshot) -> BookmarkGroup? {
        guard let data = doc.data() else { return nil }
        return BookmarkGroup(
            id:        doc.documentID,
            name:      data["name"]      as? String ?? "",
            colorHex:  data["colorHex"]  as? String ?? "F5C842",
            emoji:     data["emoji"]     as? String ?? "📖",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    // MARK: - Gratitude Posts

    func listenToGratitudeFeed(onChange: @escaping ([GratitudePost]) -> Void) -> ListenerRegistration {
        db.collection("gratitudePosts")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { snapshot, error in
                // Surface an empty list on error so the loading spinner always resolves
                guard error == nil, let snapshot else { onChange([]); return }
                let posts = snapshot.documents.compactMap { self.decodeGratitudePost($0) }
                onChange(posts)
            }
    }

    func createGratitudePost(_ post: GratitudePost) async throws {
        var data: [String: Any] = [
            "userId":       post.userId,
            "displayName":  post.displayName,
            "text":         post.text,
            "likeCount":    post.likeCount,
            "commentCount": post.commentCount,
            "createdAt":    Timestamp(date: post.createdAt)
        ]
        if let photoURL    = post.photoURL    { data["photoURL"]    = photoURL }
        if let imageURL    = post.imageURL    { data["imageURL"]    = imageURL }
        if let imageBase64 = post.imageBase64 { data["imageBase64"] = imageBase64 }
        try await db.collection("gratitudePosts").document(post.id).setData(data)
    }

    func deleteGratitudePost(id: String) async throws {
        try await db.collection("gratitudePosts").document(id).delete()
    }

    func updateGratitudePost(id: String, text: String) async throws {
        try await db.collection("gratitudePosts").document(id).updateData(["text": text])
    }

    func updateGratitudePostFields(id: String, fields: [String: Any]) async throws {
        try await db.collection("gratitudePosts").document(id).updateData(fields)
    }

    private func decodeGratitudePost(_ doc: DocumentSnapshot) -> GratitudePost? {
        guard let data = doc.data() else { return nil }
        return GratitudePost(
            id:           doc.documentID,
            userId:       data["userId"]       as? String ?? "",
            displayName:  data["displayName"]  as? String ?? "",
            photoURL:     data["photoURL"]     as? String,
            imageURL:     data["imageURL"]     as? String,
            imageBase64:  data["imageBase64"]  as? String,
            text:         data["text"]         as? String ?? "",
            likeCount:    data["likeCount"]    as? Int ?? 0,
            commentCount: data["commentCount"] as? Int ?? 0,
            createdAt:    (data["createdAt"]   as? Timestamp)?.dateValue() ?? Date()
        )
    }

    // MARK: - Gratitude Likes & Comments

    /// Adds or removes the current user's ♥ like on a gratitude post.
    func toggleGratitudeLike(postId: String, userId: String, isLiked: Bool) async throws {
        let likeRef = db.collection("gratitudePosts").document(postId)
            .collection("gratitudeLikes").document(userId)
        let postRef = db.collection("gratitudePosts").document(postId)

        if isLiked {
            try await likeRef.delete()
            try await postRef.updateData(["likeCount": FieldValue.increment(Int64(-1))])
        } else {
            try await likeRef.setData(["userId": userId, "likedAt": Timestamp(date: Date())])
            try await postRef.updateData(["likeCount": FieldValue.increment(Int64(1))])
        }
    }

    /// Returns the gratitude post IDs that this user has already liked.
    func fetchLikedGratitudeIds(userId: String) async throws -> [String] {
        let snapshot = try await db.collectionGroup("gratitudeLikes")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        return snapshot.documents
            .map { $0.reference.parent.parent?.documentID ?? "" }
            .filter { !$0.isEmpty }
    }

    /// Fetches comments for a gratitude post (oldest first).
    func fetchGratitudeComments(postId: String) async throws -> [Comment] {
        let snapshot = try await db.collection("gratitudePosts").document(postId)
            .collection("comments")
            .order(by: "createdAt")
            .getDocuments()
        return snapshot.documents.compactMap { decodeComment($0, postId: postId) }
    }

    /// Saves a comment on a gratitude post and increments its commentCount.
    func addGratitudeComment(_ comment: Comment, postId: String) async throws {
        let ref = db.collection("gratitudePosts").document(postId)
            .collection("comments").document(comment.id)
        var data: [String: Any] = [
            "userId":      comment.userId,
            "displayName": comment.displayName,
            "text":        comment.text,
            "likeCount":   0,
            "createdAt":   Timestamp(date: comment.createdAt)
        ]
        if let photoURL = comment.photoURL { data["photoURL"] = photoURL }
        if let parentId = comment.parentCommentId { data["parentCommentId"] = parentId }
        try await ref.setData(data)
        try await db.collection("gratitudePosts").document(postId).updateData([
            "commentCount": FieldValue.increment(Int64(1))
        ])
    }

    // MARK: - Prayer Requests

    func listenToPrayerFeed(onChange: @escaping ([PrayerRequest]) -> Void) -> ListenerRegistration {
        db.collection("prayerRequests")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { snapshot, error in
                // Surface an empty list on error so the loading spinner always resolves
                guard error == nil, let snapshot else { onChange([]); return }
                let requests = snapshot.documents.compactMap { self.decodePrayerRequest($0) }
                onChange(requests)
            }
    }

    func createPrayerRequest(_ request: PrayerRequest) async throws {
        var data: [String: Any] = [
            "userId":       request.userId,
            "displayName":  request.displayName,
            "text":         request.text,
            "prayingCount": request.prayingCount,
            "commentCount": request.commentCount,
            "createdAt":    Timestamp(date: request.createdAt)
        ]
        if let photoURL = request.photoURL { data["photoURL"] = photoURL }
        try await db.collection("prayerRequests").document(request.id).setData(data)
    }

    func deletePrayerRequest(id: String) async throws {
        try await db.collection("prayerRequests").document(id).delete()
    }

    func updatePrayerRequest(id: String, text: String) async throws {
        try await db.collection("prayerRequests").document(id).updateData(["text": text])
    }

    func updatePrayerRequestFields(id: String, fields: [String: Any]) async throws {
        try await db.collection("prayerRequests").document(id).updateData(fields)
    }

    /// Adds or removes the user's 🙏 on a prayer request and adjusts the count.
    func togglePraying(requestId: String, userId: String, isPraying: Bool) async throws {
        let prayingRef = db.collection("prayerRequests").document(requestId)
            .collection("prayingUsers").document(userId)
        let requestRef = db.collection("prayerRequests").document(requestId)

        if isPraying {
            // Already praying → remove
            try await prayingRef.delete()
            try await requestRef.updateData(["prayingCount": FieldValue.increment(Int64(-1))])
        } else {
            // Not yet praying → add
            try await prayingRef.setData(["userId": userId, "prayedAt": Timestamp(date: Date())])
            try await requestRef.updateData(["prayingCount": FieldValue.increment(Int64(1))])
        }
    }

    /// Returns the IDs of prayer requests that this user has already prayed for.
    func fetchPrayingIds(userId: String) async throws -> [String] {
        // collectionGroup lets us query across all "prayingUsers" subcollections
        let snapshot = try await db.collectionGroup("prayingUsers")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        return snapshot.documents.map { $0.reference.parent.parent?.documentID ?? "" }
            .filter { !$0.isEmpty }
    }

    func fetchPrayerComments(requestId: String) async throws -> [Comment] {
        let snapshot = try await db.collection("prayerRequests").document(requestId)
            .collection("comments")
            .order(by: "createdAt")
            .getDocuments()
        return snapshot.documents.compactMap { decodeComment($0, postId: requestId) }
    }

    func addPrayerComment(_ comment: Comment, requestId: String) async throws {
        let ref = db.collection("prayerRequests").document(requestId)
            .collection("comments").document(comment.id)
        var data: [String: Any] = [
            "userId":      comment.userId,
            "displayName": comment.displayName,
            "text":        comment.text,
            "likeCount":   0,
            "createdAt":   Timestamp(date: comment.createdAt)
        ]
        if let photoURL = comment.photoURL { data["photoURL"] = photoURL }
        if let parentId = comment.parentCommentId { data["parentCommentId"] = parentId }
        try await ref.setData(data)
        try await db.collection("prayerRequests").document(requestId).updateData([
            "commentCount": FieldValue.increment(Int64(1))
        ])
    }

    private func decodePrayerRequest(_ doc: DocumentSnapshot) -> PrayerRequest? {
        guard let data = doc.data() else { return nil }
        return PrayerRequest(
            id:           doc.documentID,
            userId:       data["userId"]       as? String ?? "",
            displayName:  data["displayName"]  as? String ?? "",
            photoURL:     data["photoURL"]     as? String,
            text:         data["text"]         as? String ?? "",
            prayingCount: data["prayingCount"] as? Int ?? 0,
            commentCount: data["commentCount"] as? Int ?? 0,
            createdAt:    (data["createdAt"]   as? Timestamp)?.dateValue() ?? Date()
        )
    }

    // MARK: - Daily Answers

    func listenToDailyAnswers(date: String, onChange: @escaping ([DailyAnswer]) -> Void) -> ListenerRegistration {
        // NOTE: Combining whereField + orderBy on different fields requires a composite
        // Firestore index. To avoid that requirement we filter by date only and sort
        // client-side in the ViewModel.
        db.collection("dailyAnswers")
            .whereField("date", isEqualTo: date)
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                // Surface an empty list on error so the loading spinner always resolves
                guard error == nil, let snapshot else { onChange([]); return }
                let answers = snapshot.documents
                    .compactMap { self.decodeDailyAnswer($0) }
                    .sorted { $0.createdAt < $1.createdAt }
                onChange(answers)
            }
    }

    func createDailyAnswer(_ answer: DailyAnswer) async throws {
        var data: [String: Any] = [
            "userId":       answer.userId,
            "displayName":  answer.displayName,
            "text":         answer.text,
            "date":         answer.date,
            "devotionDay":  answer.devotionDay,
            "likeCount":    answer.likeCount,
            "commentCount": answer.commentCount,
            "createdAt":    Timestamp(date: answer.createdAt)
        ]
        if let photoURL = answer.photoURL { data["photoURL"] = photoURL }
        try await db.collection("dailyAnswers").document(answer.id).setData(data)
    }

    func deleteDailyAnswer(id: String) async throws {
        try await db.collection("dailyAnswers").document(id).delete()
    }

    func updateDailyAnswer(id: String, text: String) async throws {
        try await db.collection("dailyAnswers").document(id).updateData(["text": text])
    }

    func updateDailyAnswerFields(id: String, fields: [String: Any]) async throws {
        try await db.collection("dailyAnswers").document(id).updateData(fields)
    }

    /// Adds or removes the current user's ♥ like on a daily answer.
    func toggleAnswerLike(answerId: String, userId: String, isLiked: Bool) async throws {
        let likeRef   = db.collection("dailyAnswers").document(answerId)
            .collection("answerLikes").document(userId)
        let answerRef = db.collection("dailyAnswers").document(answerId)

        if isLiked {
            // Already liked → unlike
            try await likeRef.delete()
            try await answerRef.updateData(["likeCount": FieldValue.increment(Int64(-1))])
        } else {
            // Not yet liked → like
            try await likeRef.setData(["userId": userId, "likedAt": Timestamp(date: Date())])
            try await answerRef.updateData(["likeCount": FieldValue.increment(Int64(1))])
        }
    }

    /// Returns the answer IDs that this user has already liked.
    func fetchLikedAnswerIds(userId: String) async throws -> [String] {
        let snapshot = try await db.collectionGroup("answerLikes")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        return snapshot.documents
            .map { $0.reference.parent.parent?.documentID ?? "" }
            .filter { !$0.isEmpty }
    }

    /// Fetches comments for a daily answer (oldest first).
    func fetchAnswerComments(answerId: String) async throws -> [Comment] {
        let snapshot = try await db.collection("dailyAnswers").document(answerId)
            .collection("comments")
            .order(by: "createdAt")
            .getDocuments()
        return snapshot.documents.compactMap { decodeComment($0, postId: answerId) }
    }

    /// Saves a comment on a daily answer and increments the commentCount.
    func addAnswerComment(_ comment: Comment, answerId: String) async throws {
        let ref = db.collection("dailyAnswers").document(answerId)
            .collection("comments").document(comment.id)
        var data: [String: Any] = [
            "userId":      comment.userId,
            "displayName": comment.displayName,
            "text":        comment.text,
            "likeCount":   0,
            "createdAt":   Timestamp(date: comment.createdAt)
        ]
        if let photoURL = comment.photoURL { data["photoURL"] = photoURL }
        if let parentId = comment.parentCommentId { data["parentCommentId"] = parentId }
        try await ref.setData(data)
        try await db.collection("dailyAnswers").document(answerId).updateData([
            "commentCount": FieldValue.increment(Int64(1))
        ])
    }

    private func decodeDailyAnswer(_ doc: DocumentSnapshot) -> DailyAnswer? {
        guard let data = doc.data() else { return nil }
        return DailyAnswer(
            id:           doc.documentID,
            userId:       data["userId"]       as? String ?? "",
            displayName:  data["displayName"]  as? String ?? "",
            photoURL:     data["photoURL"]     as? String,
            text:         data["text"]         as? String ?? "",
            date:         data["date"]         as? String ?? "",
            devotionDay:  data["devotionDay"]  as? Int ?? 1,
            likeCount:    data["likeCount"]    as? Int ?? 0,
            commentCount: data["commentCount"] as? Int ?? 0,
            createdAt:    (data["createdAt"]   as? Timestamp)?.dateValue() ?? Date()
        )
    }

    // MARK: - Notes

    func saveNote(_ note: UserNote, userId: String) async throws {
        let ref = db.collection("users").document(userId)
            .collection("notes").document(note.id)
        try await ref.setData([
            "chapterId": note.chapterId,
            "text":      note.text,
            "colorHex":  note.colorHex,
            "positionX": note.positionX,
            "positionY": note.positionY,
            "createdAt": Timestamp(date: note.createdAt)
        ])
    }

    func deleteNote(id: String, userId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("notes").document(id).delete()
    }

    func fetchNotes(userId: String) async throws -> [UserNote] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("notes")
            .order(by: "createdAt")
            .getDocuments()
        return snapshot.documents.compactMap { decodeNote($0) }
    }

    private func decodeNote(_ doc: DocumentSnapshot) -> UserNote? {
        guard let data = doc.data() else { return nil }
        return UserNote(
            id:        doc.documentID,
            chapterId: data["chapterId"] as? String ?? "",
            text:      data["text"]      as? String ?? "",
            colorHex:  data["colorHex"] as? String ?? "FFFDE7",
            positionX: data["positionX"] as? Double ?? 0.5,
            positionY: data["positionY"] as? Double ?? 0.3,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    // MARK: - Daily Content (AI-generated, shared across all users)

    /// Fetches a cached AI-generated DailyEntry for the given date string ("YYYY-MM-DD").
    /// Returns nil if no entry has been generated for that date yet.
    func fetchDailyEntry(date: String) async throws -> DailyEntry? {
        let doc = try await db.collection("dailyContent").document(date).getDocument()
        guard doc.exists, let data = doc.data() else { return nil }
        return DailyEntry(
            date:                data["date"]                as? String   ?? date,
            day:                 0,
            verseId:             data["verseId"]             as? String   ?? "",
            verseReference:      data["verseReference"]      as? String   ?? "",
            prayer:              data["prayer"]              as? String   ?? "",
            devotion:            data["devotion"]            as? String   ?? "",
            affirmation:         data["affirmation"]         as? String   ?? "",
            reflectionQuestions: data["reflectionQuestions"] as? [String] ?? []
        )
    }

    /// Caches an AI-generated DailyEntry in Firestore so all users get the same content.
    func saveDailyEntry(_ entry: DailyEntry) async throws {
        try await db.collection("dailyContent").document(entry.date).setData([
            "date":                entry.date,
            "verseId":             entry.verseId,
            "verseReference":      entry.verseReference,
            "prayer":              entry.prayer,
            "devotion":            entry.devotion,
            "affirmation":         entry.affirmation,
            "reflectionQuestions": entry.reflectionQuestions,
            "generatedAt":         Timestamp(date: Date())
        ])
    }

    // MARK: - Saved Devotional Items (per user)

    func fetchSavedItems(userId: String) async throws -> [SavedDevotionalItem] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("savedItems")
            .getDocuments()
        return snapshot.documents.compactMap { decodeSavedItem($0) }
    }

    func saveDevotion(_ item: SavedDevotionalItem, userId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("savedItems").document(item.id).setData([
                "type":           item.type,
                "verseReference": item.verseReference,
                "content":        item.content,
                "entryDate":      item.entryDate,
                "savedAt":        Timestamp(date: item.savedAt)
            ])
    }

    func deleteSavedItem(id: String, userId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("savedItems").document(id).delete()
    }

    private func decodeSavedItem(_ doc: DocumentSnapshot) -> SavedDevotionalItem? {
        guard let data = doc.data() else { return nil }
        var item = SavedDevotionalItem(
            userId:         "",   // not stored per-doc (it's implicit in the path)
            type:           data["type"]           as? String ?? "",
            verseReference: data["verseReference"] as? String ?? "",
            content:        data["content"]        as? String ?? "",
            entryDate:      data["entryDate"]      as? String ?? "",
            savedAt:        (data["savedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
        item.id = doc.documentID
        return item
    }

    // MARK: - Subscription Status

    func saveSubscriptionStatus(userId: String, isPremium: Bool, productId: String?) async throws {
        var data: [String: Any] = [
            "isPremium": isPremium,
            "updatedAt": Timestamp(date: Date())
        ]
        if let productId { data["productId"] = productId }
        try await db.collection("users").document(userId).setData(
            ["subscription": data],
            merge: true
        )
    }

    func loadSubscriptionStatus(userId: String) async throws -> Bool {
        let doc = try await db.collection("users").document(userId).getDocument()
        guard let data = doc.data(),
              let sub = data["subscription"] as? [String: Any]
        else { return false }
        return sub["isPremium"] as? Bool ?? false
    }

    // MARK: - Habits

    func saveHabit(_ habit: Habit, userId: String) async throws {
        let data: [String: Any] = [
            "name":               habit.name,
            "description":        habit.description,
            "emoji":              habit.emoji,
            "colorHex":           habit.colorHex,
            "category":           habit.category,
            "habitType":          habit.habitType,
            "goalValue":          habit.goalValue,
            "goalUnit":           habit.goalUnit,
            "goalPeriod":         habit.goalPeriod,
            "taskDays":           habit.taskDays,
            "timeRange":          habit.timeRange,
            "isBibleReadingPlan": habit.isBibleReadingPlan,
            "startDate":          Timestamp(date: habit.startDate),
            "endDate":            habit.endDate.map { Timestamp(date: $0) } as Any,
            "createdAt":          Timestamp(date: habit.createdAt),
            "sortOrder":          habit.sortOrder
        ]
        try await db.collection("users").document(userId)
            .collection("habits").document(habit.id).setData(data)
    }

    func deleteHabit(id: String, userId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("habits").document(id).delete()
    }

    func fetchHabits(userId: String) async throws -> [Habit] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("habits")
            .order(by: "createdAt", descending: false)
            .getDocuments()
        return snapshot.documents.compactMap { decodeHabit($0) }
    }

    private func decodeHabit(_ doc: DocumentSnapshot) -> Habit? {
        guard let data = doc.data() else { return nil }
        return Habit(
            id:                 doc.documentID,
            name:               data["name"]               as? String ?? "",
            description:        data["description"]        as? String ?? "",
            emoji:              data["emoji"]              as? String ?? "\u{2B50}",
            colorHex:           data["colorHex"]           as? String ?? "4CAF50",
            category:           data["category"]           as? String ?? "Spiritual",
            habitType:          data["habitType"]          as? String ?? "build",
            goalValue:          data["goalValue"]          as? Int    ?? 1,
            goalUnit:           data["goalUnit"]           as? String ?? "count",
            goalPeriod:         data["goalPeriod"]         as? String ?? "daily",
            taskDays:           data["taskDays"]           as? [Int]  ?? [1,2,3,4,5,6,7],
            timeRange:          data["timeRange"]          as? String ?? "anytime",
            isBibleReadingPlan: data["isBibleReadingPlan"] as? Bool   ?? false,
            startDate:          (data["startDate"] as? Timestamp)?.dateValue() ?? Date(),
            endDate:            (data["endDate"]   as? Timestamp)?.dateValue(),
            createdAt:          (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            sortOrder:          data["sortOrder"]          as? Int    ?? 0
        )
    }

    // MARK: - Habit Logs

    func saveHabitLog(_ log: HabitLog, userId: String) async throws {
        var data: [String: Any] = [
            "habitId":     log.habitId,
            "date":        log.date,
            "value":       log.value,
            "note":        log.note,
            "completedAt": Timestamp(date: log.completedAt)
        ]
        if let chapters = log.chapters {
            data["chapters"] = chapters
        }
        try await db.collection("users").document(userId)
            .collection("habitLogs").document(log.id).setData(data)
    }

    func deleteHabitLog(id: String, userId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("habitLogs").document(id).delete()
    }

    func fetchHabitLogs(userId: String) async throws -> [HabitLog] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("habitLogs")
            .order(by: "completedAt", descending: false)
            .getDocuments()
        return snapshot.documents.compactMap { decodeHabitLog($0) }
    }

    private func decodeHabitLog(_ doc: DocumentSnapshot) -> HabitLog? {
        guard let data = doc.data() else { return nil }
        return HabitLog(
            id:          doc.documentID,
            habitId:     data["habitId"]     as? String ?? "",
            date:        data["date"]        as? String ?? "",
            value:       data["value"]       as? Int    ?? 1,
            note:        data["note"]        as? String ?? "",
            chapters:    data["chapters"]    as? [String],
            completedAt: (data["completedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
}

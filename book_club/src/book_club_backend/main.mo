import Iter "mo:base/Iter";
import Map "mo:base/OrderedMap";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Set "mo:base/OrderedSet";
import Text "mo:base/Text";

actor {
  type Result<T, E> = Result.Result<T, E>;

  type Book = BookModule.Book;
  type BookResult = BookModule.BookResult;
  type FilterBy = BookModule.FilterBy;
  type ProposeBook = BookModule.ProposeBook;

  type ReadingProgress = UserModule.ReadingProgress;
  type User = UserModule.User;
  type UserResult = UserModule.UserResult;

  type Comment = CommentModule.Comment;
  type PostComment = CommentModule.PostComment;

  let natMap = Map.Make<Nat>(Nat.compare);

  stable var nextBookID : Nat = 0;
  stable var books : Map.Map<Nat, Book> = natMap.empty<Book>();

  module BookModule {
    public type Book = {
      id : Nat;
      name : Text;
      description : Text;
      proposer : Principal;
      var votes : Nat;
      var comments : Map.Map<Nat, Comment>;
    };

    public type BookResult = {
      id : Nat;
      name : Text;
      description : Text;
      proposer : Principal;
      votes : Nat;
      comments : [Comment];
    };

    public type ProposeBook = {
      name : Text;
      description : Text;
    };

    public func initializeBook(book : ProposeBook, p : Principal) : Book {
      let newBook = {
        id = nextBookID;
        name = book.name;
        description = book.description;
        proposer = p;
        var votes = 0;
        var comments = natMap.empty<Comment>();
      };

      nextBookID += 1;
      newBook;
    };

    public func toBookResult(book : Book) : BookResult {
      {
        id = book.id;
        name = book.name;
        description = book.description;
        proposer = book.proposer;
        votes = book.votes;
        comments = Iter.toArray(natMap.vals(book.comments));
      };
    };

    public type FilterBy = {
      #all;
      #byName : Text;
      #byDescription : Text;
      #byProposer : Principal;
      #byVotes : Nat;
    };

    public func filterBooks(filter : FilterBy) : Result<[BookResult], Text> {
      func bookFilter(_key : Nat, val : Book) : ?BookResult {
        switch filter {
          case (#all) {
            ?toBookResult(val);
          };
          case (#byName(name)) {
            // Trim in the future.
            if (Text.contains(val.name, #text name)) ?toBookResult(val) else null;
          };
          case (#byDescription(description)) {
            // Trim in the future.
            if (Text.contains(val.description, #text description)) ?toBookResult(val) else null;
          };
          case (#byProposer(principal)) {
            if (val.proposer == principal) ?toBookResult(val) else null;
          };
          case (#byVotes(votes)) {
            if (val.votes >= votes) ?toBookResult(val) else null;
          };
        };
      };

      let newMap = natMap.mapFilter(books, bookFilter);

      if (natMap.size(newMap) == 0) {
        return #err("No book meets " # debug_show (filter) # ".");
      };

      #ok(Iter.toArray(natMap.vals(newMap)));
    };
  };

  let userMap = Map.Make<Principal>(Principal.compare);
  stable var users : Map.Map<Principal, User> = userMap.empty<User>();

  let bookSet = Set.Make<Nat>(Nat.compare);

  module UserModule {
    public type ReadingProgress = {
      bookId : Nat;
      progress : Nat8;
    };

    public type User = {
      principal : Principal;
      var proposedBooks : Set.Set<Nat>;
      var votedBooks : Set.Set<Nat>;
      var progressTracking : Map.Map<Nat, ReadingProgress>;
      // Track all comments in the future.
    };

    public type UserResult = {
      principal : Principal;
      proposedBooks : [Nat];
      votedBooks : [Nat];
      progressTracking : [ReadingProgress];
    };

    public func getOrInitializeUser(principal : Principal) : User {
      switch (userMap.get(users, principal)) {
        case null {
          {
            principal = principal;
            var proposedBooks = bookSet.empty();
            var votedBooks = bookSet.empty();
            var progressTracking = natMap.empty<ReadingProgress>();
          };
        };
        case (?user) {
          user;
        };
      };
    };

    public func toUserResult(user : User) : UserResult {
      {
        principal = user.principal;
        proposedBooks = Iter.toArray(bookSet.vals(user.proposedBooks));
        votedBooks = Iter.toArray(bookSet.vals(user.votedBooks));
        progressTracking = Iter.toArray(natMap.vals(user.progressTracking));
      };
    };
  };

  stable var nextCommentID : Nat = 0;

  module CommentModule {
    public type Comment = {
      id : Nat;
      commenter : Principal;
      bookId : Nat;
      comment : Text;
    };

    public type PostComment = {
      bookId : Nat;
      comment : Text;
    };

    public func initializeComment(postComment : PostComment, p : Principal) : Comment {
      let newComment = {
        id = nextCommentID;
        commenter = p;
        bookId = postComment.bookId;
        comment = postComment.comment;
      };

      nextCommentID += 1;
      newComment;
    };
  };

  public shared ({ caller }) func proposeBook(book : ProposeBook) : async Result<Nat, Text> {
    if (Principal.isAnonymous(caller)) {
      return #err("An anonymous user is not allowed to propose.");
    };

    // Simply use a generated book id as the key.
    let newBook = BookModule.initializeBook(book, caller);
    books := natMap.put(books, newBook.id, newBook);

    let user = UserModule.getOrInitializeUser(caller);
    user.proposedBooks := bookSet.put(user.proposedBooks, newBook.id);
    users := userMap.put(users, caller, user);

    #ok(newBook.id);
  };

  public query func getBookById(id : Nat) : async Result<BookResult, Text> {
    switch (natMap.get(books, id)) {
      case null #err("Book with id " # Nat.toText(id) # " does not exist.");
      case (?book) #ok(BookModule.toBookResult(book));
    };
  };

  public query func getAllBooks() : async Result<[BookResult], Text> {
    BookModule.filterBooks(#all);
  };

  public query func getBooksByName(name : Text) : async Result<[BookResult], Text> {
    BookModule.filterBooks(#byName(name));
  };

  public query func getBooksByDescription(description : Text) : async Result<[BookResult], Text> {
    BookModule.filterBooks(#byDescription(description));
  };

  public query func getBooksByProposer(proposer : Principal) : async Result<[BookResult], Text> {
    BookModule.filterBooks(#byProposer(proposer));
  };

  public query func getBooksByVotes(votes : Nat) : async Result<[BookResult], Text> {
    BookModule.filterBooks(#byVotes(votes));
  };

  public shared ({ caller }) func voteOnBook(bookId : Nat) : async Result<(), Text> {
    if (Principal.isAnonymous(caller)) {
      return #err("An anonymous user is not allowed to vote.");
    };

    let ?book = natMap.get(books, bookId) else return #err("Book with id " # Nat.toText(bookId) # " does not exist.");

    let user = UserModule.getOrInitializeUser(caller);
    if (bookSet.contains((user.votedBooks, bookId))) {
      return #err("You have already voted for book " # Nat.toText(bookId) # ".");
    };

    book.votes += 1;
    user.votedBooks := bookSet.put(user.votedBooks, bookId);

    #ok();
  };

  public shared ({ caller }) func unvoteOnBook(bookId : Nat) : async Result<(), Text> {
    if (Principal.isAnonymous(caller)) {
      return #err("An anonymous user is not allowed to unvote.");
    };

    let ?book = natMap.get(books, bookId) else return #err("Book with id " # Nat.toText(bookId) # " does not exist.");

    let user = UserModule.getOrInitializeUser(caller);
    if (not bookSet.contains((user.votedBooks, bookId))) {
      return #err("You have not voted for book " # Nat.toText(bookId) # ".");
    };

    book.votes -= 1;
    user.votedBooks := bookSet.delete(user.votedBooks, bookId);

    #ok();
  };

  public shared ({ caller }) func commentOnBook(comment : PostComment) : async Result<(), Text> {
    if (Principal.isAnonymous(caller)) {
      return #err("An anonymous user is not allowed to comment.");
    };

    let ?book = natMap.get(books, comment.bookId) else return #err("Book with id " # Nat.toText(comment.bookId) # " does not exist.");
    let newComment = CommentModule.initializeComment(comment, caller);
    book.comments := natMap.put(book.comments, newComment.id, newComment);

    #ok();
  };

  public query func getUserByPrincipal(principal : Principal) : async Result<UserResult, Text> {
    // Now everyone can check any user information, we can add the check easily if it's necessary.
    let ?user = userMap.get(users, principal) else return #err("User with principal " # Principal.toText(principal) # " does not exist.");
    #ok(UserModule.toUserResult(user));
  };

  public shared ({ caller }) func updateReadingProgressOnBook(progress : ReadingProgress) : async Result<(), Text> {
    if (Principal.isAnonymous(caller)) {
      return #err("An anonymous user is not allowed to update reading progress.");
    };

    if (progress.progress > 100) {
      return #err("Reading progress must be between 0 and 100.");
    };

    let user = UserModule.getOrInitializeUser(caller);
    user.progressTracking := natMap.put(user.progressTracking, progress.bookId, progress);

    #ok();
  };
};

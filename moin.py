import time
import random

def punderdome_3000():
    puns = [
        {"q": "Why did the chicken join a band?", "a": ["Because it had drumsticks!", "To lay down the cluck track!", "For the egg-cellent gig!"]},
        {"q": "What do you call fake spaghetti?", "a": ["An impasta!", "Mama mia-gination!", "Noodle-doodle!"]},
        {"q": "Why don't skeletons fight each other?", "a": ["They don't have the guts!", "Too bone-tired!", "Can't stomach violence!"]}
    ]
    
    print("Welcome to PUNDERDOME 3000!\n")
    time.sleep(1)
    print("⚡️ Prepare for the ULTIMATE PUN SHOWDOWN ⚡️\n")
    time.sleep(2)
    
    score = 0
    for _ in range(3):
        pun = random.choice(puns)
        print(f"PUN CHALLENGE: {pun['q']}")
        answer = input("Your punny response: ").strip().lower()
        
        if any(keyword in answer for keyword in ["because", "to", "for"]):
            print(f"\nROBOT JUDGE: {random.choice(pun['a'])}")
            score += random.randint(1, 5)
            print(f"Current Cringe Level: {score}/15\n")
        else:
            print("\nROBOT JUDGE: *BZZT* That's not even a proper pun structure! -5 points!\n")
            score -= 5
            
        time.sleep(1)
    
    print("\nFINAL RESULTS:")
    if score > 10:
        print("🏆 PUN MASTER! You've achieved maximum groans!")
    elif score > 0:
        print("🎩 PUN APPRENTICE! The dad joke force is strong with you!")
    else:
        print("💩 PUN CRIMINAL! Your license to pun is REVOKED!")
    
    print(f"\nFinal Cringe Score: {score} - Thanks for playing Punderdome 3000!")

if __name__ == "__main__":
    punderdome_3000()
